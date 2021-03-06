require 'date'
require 'timeout'
require 'test/unit'

# Make all the assert_* methods easily accessible in any context.
include Test::Unit::Assertions

def assert_vmcommand_success(p, msg = nil)
  assert(p.success?, msg.nil? ? "Command failed: #{p.cmd}\n" + \
                                "error code: #{p.returncode}\n" \
                                "stderr: #{p.stderr}" : \
                                msg)
end

# It's forbidden to throw this exception (or subclasses) in anything
# but try_for() below. Just don't use it anywhere else!
class UniqueTryForTimeoutError < Exception
end

# Call block (ignoring any exceptions it may throw) repeatedly with
# one second breaks until it returns true, or until `timeout` seconds have
# passed when we throw a Timeout::Error exception.
def try_for(timeout, options = {})
  options[:delay] ||= 1
  # Create a unique exception used only for this particular try_for
  # call's Timeout to allow nested try_for:s. If we used the same one,
  # the innermost try_for would catch all outer ones', creating a
  # really strange situation.
  unique_timeout_exception = Class.new(UniqueTryForTimeoutError)
  Timeout::timeout(timeout, unique_timeout_exception) do
    loop do
      begin
        return if yield
      rescue NameError, UniqueTryForTimeoutError => e
        # NameError most likely means typos, and hiding that is rarely
        # (never?) a good idea, so we rethrow them. See below why we
        # also rethrow *all* the unique exceptions.
        raise e
      rescue Exception
        # All other exceptions are ignored while trying the block.
      end
      sleep options[:delay]
    end
  end
  # At this point the block above either succeeded and we'll return,
  # or we are throwing an exception. If the latter, we either have a
  # NameError that we'll not catch (and will any try_for below us in
  # the stack), or we have a unique exception. That can mean one of
  # two things:
  # 1. it's the one unique to this try_for, and in that case we'll
  #    catch it, rethrowing it as something that will be ignored by
  #    inside the blocks of all try_for:s below us in the stack.
  # 2. it's an exception unique to another try_for. Assuming that we
  #    do not throw the unique exceptions in any other place or way
  #    than we do it in this function, this means that there is a
  #    try_for below us in the stack to which this exception must be
  #    unique to.
  # Let 1 be the base step, and 2 the inductive step, and we sort of
  # an inductive proof for the correctness of try_for when it's
  # nested. It shows that for an infinite stack of try_for:s, any of
  # the unique exceptions will be caught only by the try_for instance
  # it is unique to, and all try_for:s in between will ignore it so it
  # ends up there immediately.
rescue unique_timeout_exception => e
  msg = options[:msg] || 'try_for() timeout expired'
  raise Timeout::Error.new(msg)
end

class TorFailure < StandardError
end

# This will retry the block up to MAX_NEW_TOR_CIRCUIT_RETRIES
# times. The block must raise an exception for a run to be considered
# as a failure. After a failure recovery_proc will be called (if
# given) and the intention with it is to bring us back to the state
# expected by the block, so it can be retried.
def retry_tor(recovery_proc = nil, &block)
  max_retries = $config["MAX_NEW_TOR_CIRCUIT_RETRIES"]
  retries = 1
  loop do
    begin
      block.call
      return
    rescue Exception => e
      if retries <= max_retries
        if $config["DEBUG"]
          STDERR.puts "Tor operation failed (Tor circuit try #{retries} of " +
                      "#{max_retries}) with:\n" +
                      "#{e.class}: #{e.message}"
        end
        recovery_proc.call if recovery_proc
        force_new_tor_circuit
        retries += 1
      else
        raise TorFailure.new("The operation failed (despite forcing " +
                             "#{max_retries} new Tor circuits) with\n" +
                             "#{e.class}: #{e.message}")
      end
    end
  end
end

def wait_until_tor_is_working
  try_for(270) { @vm.execute(
    '. /usr/local/lib/tails-shell-library/tor.sh; tor_is_working').success? }
end

def convert_bytes_mod(unit)
  case unit
  when "bytes", "b" then mod = 1
  when "KB"         then mod = 10**3
  when "k", "KiB"   then mod = 2**10
  when "MB"         then mod = 10**6
  when "M", "MiB"   then mod = 2**20
  when "GB"         then mod = 10**9
  when "G", "GiB"   then mod = 2**30
  when "TB"         then mod = 10**12
  when "T", "TiB"   then mod = 2**40
  else
    raise "invalid memory unit '#{unit}'"
  end
  return mod
end

def convert_to_bytes(size, unit)
  return (size*convert_bytes_mod(unit)).to_i
end

def convert_to_MiB(size, unit)
  return (size*convert_bytes_mod(unit) / (2**20)).to_i
end

def convert_from_bytes(size, unit)
  return size.to_f/convert_bytes_mod(unit).to_f
end

def cmd_helper(cmd)
  if cmd.instance_of?(Array)
    cmd << {:err => [:child, :out]}
  elsif cmd.instance_of?(String)
    cmd += " 2>&1"
  end
  IO.popen(cmd) do |p|
    out = p.readlines.join("\n")
    p.close
    ret = $?
    assert_equal(0, ret, "Command failed (returned #{ret}): #{cmd}:\n#{out}")
    return out
  end
end

# This command will grab all router IP addresses from the Tor
# consensus in the VM + the hardcoded TOR_AUTHORITIES.
def get_all_tor_nodes
  cmd = 'awk "/^r/ { print \$6 }" /var/lib/tor/cached-microdesc-consensus'
  @vm.execute(cmd).stdout.chomp.split("\n") + TOR_AUTHORITIES
end

def get_free_space(machine, path)
  case machine
  when 'host'
    assert(File.exists?(path), "Path '#{path}' not found on #{machine}.")
    free = cmd_helper(["df", path])
  when 'guest'
    assert(@vm.file_exist?(path), "Path '#{path}' not found on #{machine}.")
    free = @vm.execute_successfully("df '#{path}'")
  else
    raise 'Unsupported machine type #{machine} passed.'
  end
  output = free.split("\n").last
  return output.match(/[^\s]\s+[0-9]+\s+[0-9]+\s+([0-9]+)\s+.*/)[1].chomp.to_i
end

def random_string_from_set(set, min_len, max_len)
  len = (min_len..max_len).to_a.sample
  len ||= min_len
  (0..len-1).map { |n| set.sample }.join
end

def random_alpha_string(min_len, max_len = 0)
  alpha_set = ('A'..'Z').to_a + ('a'..'z').to_a
  random_string_from_set(alpha_set, min_len, max_len)
end

def random_alnum_string(min_len, max_len = 0)
  alnum_set = ('A'..'Z').to_a + ('a'..'z').to_a + (0..9).to_a.map { |n| n.to_s }
  random_string_from_set(alnum_set, min_len, max_len)
end

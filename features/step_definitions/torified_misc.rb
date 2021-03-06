When /^I query the whois directory service for "([^"]+)"$/ do |domain|
  next if @skip_steps_while_restoring_background
  retry_tor do
    @vm_execute_res = @vm.execute("whois '#{domain}'", LIVE_USER)
    if @vm_execute_res.failure?
      raise "Looking up whois info for #{domain} failed with:\n" +
            "#{@vm_execute_res.stdout}\n" +
            "#{@vm_execute_res.stderr}"
    end
  end
end

When /^I wget "([^"]+)" to stdout(?:| with the '([^']+)' options)$/ do |url, options|
  next if @skip_steps_while_restoring_background
  arguments = "-O - '#{url}'"
  arguments = "#{options} #{arguments}" if options
  retry_tor do
    @vm_execute_res = @vm.execute("wget #{arguments}", LIVE_USER)
    if @vm_execute_res.failure?
      raise "wget:ing #{url} with options #{options} failed with:\n" +
            "#{@vm_execute_res.stdout}\n" +
            "#{@vm_execute_res.stderr}"
    end
  end
end

Then /^the (wget|whois) command is successful$/ do |command|
  next if @skip_steps_while_restoring_background
  assert(
    @vm_execute_res.success?,
    "#{command} failed:\n" +
    "#{@vm_execute_res.stdout}\n" +
    "#{@vm_execute_res.stderr}"
  )
end

Then /^the (wget|whois) standard output contains "([^"]+)"$/ do |command, text|
  next if @skip_steps_while_restoring_background
  assert(
    @vm_execute_res.stdout[text],
    "The #{command} standard output does not contain #{text}:\n" +
    "#{@vm_execute_res.stdout}\n" +
    "#{@vm_execute_res.stderr}"
  )
end

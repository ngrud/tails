# Extracts the secrets for the XMMP account `account_name`.
def xmpp_account(account_name, required_options = [])
  begin
    account = $config["Pidgin"]["Accounts"]["XMPP"][account_name]
    check_keys = ["username", "domain", "password"] + required_options
    for key in check_keys do
      assert(account.has_key?(key))
      assert_not_nil(account[key])
      assert(!account[key].empty?)
    end
  rescue NoMethodError, Test::Unit::AssertionFailedError
    raise(
<<EOF
Your Pidgin:Accounts:XMPP:#{account} is incorrect or missing from your local configuration file (#{LOCAL_CONFIG_FILE}). See wiki/src/contribute/release_process/test/usage.mdwn for the format.
EOF
)
  end
  return account
end

def wait_and_focus(img, time = 10, window)
  begin
    @screen.wait(img, time)
  rescue FindFailed
    @vm.focus_window(window)
    @screen.wait(img, time)
  end
end

def focus_pidgin_irc_conversation_window(account)
  account = account.sub(/^irc\./, '')
  @vm.focus_window(".*#{Regexp.escape(account)}$")
end

When /^I create my XMPP account$/ do
  next if @skip_steps_while_restoring_background
  account = xmpp_account("Tails_account")
  @screen.click("PidginAccountManagerAddButton.png")
  @screen.wait("PidginAddAccountWindow.png", 20)
  @screen.click_mid_right_edge("PidginAddAccountProtocolLabel.png")
  @screen.click("PidginAddAccountProtocolXMPP.png")
  @screen.click_mid_right_edge("PidginAddAccountXMPPUsername.png")
  @screen.type(account["username"])
  @screen.click_mid_right_edge("PidginAddAccountXMPPDomain.png")
  @screen.type(account["domain"])
  @screen.click_mid_right_edge("PidginAddAccountXMPPPassword.png")
  @screen.type(account["password"])
  @screen.click("PidginAddAccountXMPPRememberPassword.png")
  if account["connect_server"]
    @screen.click("PidginAddAccountXMPPAdvancedTab.png")
    @screen.click_mid_right_edge("PidginAddAccountXMPPConnectServer.png")
    @screen.type(account["connect_server"])
  end
  @screen.click("PidginAddAccountXMPPAddButton.png")
end

Then /^Pidgin automatically enables my XMPP account$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window('Buddy List')
  @screen.wait("PidginAvailableStatus.png", 120)
end

Given /^my XMPP friend goes online( and joins the multi-user chat)?$/ do |join_chat|
  next if @skip_steps_while_restoring_background
  account = xmpp_account("Friend_account", ["otr_key"])
  bot_opts = account.select { |k, v| ["connect_server"].include?(k) }
  if join_chat
    bot_opts["auto_join"] = [@chat_room_jid]
  end
  @friend_name = account["username"]
  @chatbot = ChatBot.new(account["username"] + "@" + account["domain"],
                         account["password"], account["otr_key"], bot_opts)
  @chatbot.start
  add_after_scenario_hook { @chatbot.stop }
  @vm.focus_window('Buddy List')
  @screen.wait("PidginFriendOnline.png", 60)
end

When /^I start a conversation with my friend$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window('Buddy List')
  # Clicking the middle, bottom of this image should query our
  # friend, given it's the only subscribed user that's online, which
  # we assume.
  r = @screen.find("PidginFriendOnline.png")
  bottom_left = r.getBottomLeft()
  x = bottom_left.getX + r.getW/2
  y = bottom_left.getY
  @screen.doubleClick_point(x, y)
  # Since Pidgin sets the window name to the contact, we have no good
  # way to identify the conversation window. Let's just look for the
  # expected menu bar.
  @screen.wait("PidginConversationWindowMenuBar.png", 10)
end

And /^I say something to my friend( in the multi-user chat)?$/ do |multi_chat|
  next if @skip_steps_while_restoring_background
  msg = "ping" + Sikuli::Key.ENTER
  if multi_chat
    @vm.focus_window(@chat_room_jid.split("@").first)
    msg = @friend_name + ": " + msg
  else
    @vm.focus_window(@friend_name)
  end
  @screen.type(msg)
end

Then /^I receive a response from my friend( in the multi-user chat)?$/ do |multi_chat|
  next if @skip_steps_while_restoring_background
  if multi_chat
    @vm.focus_window(@chat_room_jid.split("@").first)
  else
    @vm.focus_window(@friend_name)
  end
  @screen.wait("PidginFriendExpectedAnswer.png", 20)
end

When /^I start an OTR session with my friend$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window(@friend_name)
  @screen.click("PidginConversationOTRMenu.png")
  @screen.hide_cursor
  @screen.click("PidginOTRMenuStartSession.png")
end

Then /^Pidgin automatically generates an OTR key$/ do
  next if @skip_steps_while_restoring_background
  @screen.wait("PidginOTRKeyGenPrompt.png", 30)
  @screen.wait_and_click("PidginOTRKeyGenPromptDoneButton.png", 30)
end

Then /^an OTR session was successfully started with my friend$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window(@friend_name)
  @screen.wait("PidginConversationOTRUnverifiedSessionStarted.png", 10)
end

# The reason the chat must be empty is to guarantee that we don't mix
# up messages/events from other users with the ones we expect from the
# bot.
When /^I join some empty multi-user chat$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window('Buddy List')
  @screen.click("PidginBuddiesMenu.png")
  @screen.wait_and_click("PidginBuddiesMenuJoinChat.png", 10)
  @screen.wait_and_click("PidginJoinChatWindow.png", 10)
  @screen.click_mid_right_edge("PidginJoinChatRoomLabel.png")
  account = xmpp_account("Tails_account")
  if account.has_key?("chat_room") && \
     !account["chat_room"].nil? && \
     !account["chat_room"].empty?
    chat_room = account["chat_room"]
  else
    chat_room = random_alnum_string(10, 15)
  end
  @screen.type(chat_room)

  # We will need the conference server later, when starting the bot.
  @screen.click_mid_right_edge("PidginJoinChatServerLabel.png")
  @screen.type("a", Sikuli::KeyModifier.CTRL)
  @screen.type("c", Sikuli::KeyModifier.CTRL)
  conference_server =
    @vm.execute_successfully("xclip -o", LIVE_USER).stdout.chomp
  @chat_room_jid = chat_room + "@" + conference_server

  @screen.click("PidginJoinChatButton.png")
  # The following will both make sure that the we joined the chat, and
  # that it is empty. We'll also deal with the *potential* "Create New
  # Room" prompt that Pidgin shows for some server configurations.
  images = ["PidginCreateNewRoomPrompt.png",
            "PidginChat1UserInRoom.png"]
  image_found, _ = @screen.waitAny(images, 30)
  if image_found == "PidginCreateNewRoomPrompt.png"
    @screen.click("PidginCreateNewRoomAcceptDefaultsButton.png")
  end
  @vm.focus_window(@chat_room_jid)
  @screen.wait("PidginChat1UserInRoom.png", 10)
end

# Since some servers save the scrollback, and sends it when joining,
# it's safer to clear it so we do not get false positives from old
# messages when looking for a particular response, or similar.
When /^I clear the multi-user chat's scrollback$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window(@chat_room_jid)
  @screen.click("PidginConversationMenu.png")
  @screen.wait_and_click("PidginConversationMenuClearScrollback.png", 10)
end

Then /^I can see that my friend joined the multi-user chat$/ do
  next if @skip_steps_while_restoring_background
  @vm.focus_window(@chat_room_jid)
  @screen.wait("PidginChat2UsersInRoom.png", 60)
end

def configured_pidgin_accounts
  accounts = Hash.new
  xml = REXML::Document.new(@vm.file_content('$HOME/.purple/accounts.xml',
                                             LIVE_USER))
  xml.elements.each("account/account") do |e|
    account   = e.elements["name"].text
    account_name, network = account.split("@")
    protocol  = e.elements["protocol"].text
    port      = e.elements["settings/setting[@name='port']"].text
    nickname  = e.elements["settings/setting[@name='username']"].text
    real_name = e.elements["settings/setting[@name='realname']"].text
    accounts[network] = {
      'name'      => account_name,
      'network'   => network,
      'protocol'  => protocol,
      'port'      => port,
      'nickname'  => nickname,
      'real_name' => real_name,
    }
  end

  return accounts
end

def chan_image (account, channel, image)
  images = {
    'irc.oftc.net' => {
      '#tails' => {
        'roster'           => 'PidginTailsChannelEntry',
        'conversation_tab' => 'PidginTailsConversationTab',
        'welcome'          => 'PidginTailsChannelWelcome',
      }
    }
  }
  return images[account][channel][image] + ".png"
end

def default_chan (account)
  chans = {
    'irc.oftc.net' => '#tails',
  }
  return chans[account]
end

def pidgin_otr_keys
  return @vm.file_content('$HOME/.purple/otr.private_key', LIVE_USER)
end

Given /^Pidgin has the expected accounts configured with random nicknames$/ do
  next if @skip_steps_while_restoring_background
  expected = [
            ["irc.oftc.net", "prpl-irc", "6697"],
            ["127.0.0.1",    "prpl-irc", "6668"],
          ]
  configured_pidgin_accounts.values.each() do |account|
    assert(account['nickname'] != "XXX_NICK_XXX", "Nickname was no randomised")
    assert_equal(account['nickname'], account['real_name'],
                 "Nickname and real name are not identical: " +
                 account['nickname'] + " vs. " + account['real_name'])
    assert_equal(account['name'], account['nickname'],
                 "Account name and nickname are not identical: " +
                 account['name'] + " vs. " + account['nickname'])
    candidate = [account['network'], account['protocol'], account['port']]
    assert(expected.include?(candidate), "Unexpected account: #{candidate}")
    expected.delete(candidate)
  end
  assert(expected.empty?, "These Pidgin accounts are not configured: " +
         "#{expected}")
end

When /^I start Pidgin through the GNOME menu$/ do
  next if @skip_steps_while_restoring_background
  step 'I start "Pidgin" via the GNOME "Internet" applications menu'
end

When /^I open Pidgin's account manager window$/ do
  next if @skip_steps_while_restoring_background
  @screen.type("a", Sikuli::KeyModifier.CTRL) # shortcut for "manage accounts"
  step "I see Pidgin's account manager window"
end

When /^I see Pidgin's account manager window$/ do
  next if @skip_steps_while_restoring_background
  @screen.wait("PidginAccountWindow.png", 40)
end

When /^I close Pidgin's account manager window$/ do
  next if @skip_steps_while_restoring_background
  @screen.wait_and_click("PidginAccountManagerCloseButton.png", 10)
end

When /^I activate the "([^"]+)" Pidgin account$/ do |account|
  next if @skip_steps_while_restoring_background
  @screen.click("PidginAccount_#{account}.png")
  @screen.type(Sikuli::Key.LEFT + Sikuli::Key.SPACE)
  # wait for the Pidgin to be connecting, otherwise sometimes the step
  # that closes the account management dialog happens before the account
  # is actually enabled
  @screen.wait("PidginConnecting.png", 5)
end

Then /^Pidgin successfully connects to the "([^"]+)" account$/ do |account|
  next if @skip_steps_while_restoring_background
  expected_channel_entry = chan_image(account, default_chan(account), 'roster')
  reconnect_button = 'PidginReconnect.png'
  recovery_on_failure = Proc.new do
    @screen.wait_and_click(reconnect_button, 20)
  end
  retry_tor(recovery_on_failure) do
    begin
      @vm.focus_window('Buddy List')
    rescue ExecutionFailedInVM
      # Sometimes focusing the window with xdotool will fail with the
      # conversation window right on top of it. We'll try to close the
      # conversation window. At worst, the test will still fail...
      close_pidgin_conversation_window(account)
    end
    on_screen, _ = @screen.waitAny([expected_channel_entry, reconnect_button], 60)
    unless on_screen == expected_channel_entry
      raise "Connecting to account #{account} failed."
    end
  end
end

Then /^the "([^"]*)" account only responds to PING and VERSION CTCP requests$/ do |irc_server|
  next if @skip_steps_while_restoring_background
  ctcp_cmds = [
    "CLIENTINFO", "DATE", "ERRMSG", "FINGER", "PING", "SOURCE", "TIME",
    "USERINFO", "VERSION"
  ]
  expected_ctcp_replies = {
    "PING" => /^\d+$/,
    "VERSION" => /^Purple IRC$/
  }
  spam_target = configured_pidgin_accounts[irc_server]["nickname"]
  ctcp_check = CtcpChecker.new(irc_server, 6667, spam_target, ctcp_cmds,
                               expected_ctcp_replies)
  ctcp_check.verify_ctcp_responses
end

Then /^I can join the "([^"]+)" channel on "([^"]+)"$/ do |channel, account|
  next if @skip_steps_while_restoring_background
  @screen.doubleClick(   chan_image(account, channel, 'roster'))
  @screen.hide_cursor
  focus_pidgin_irc_conversation_window(account)
  try_for(60) do
    begin
      @screen.wait_and_click(chan_image(account, channel, 'conversation_tab'), 5)
    rescue FindFailed => e
      # If the channel tab can't be found it could be because there were
      # multiple connection attempts and the channel tab we want is off the
      # screen. We'll try closing tabs until the one we want can be found.
      @screen.type("w", Sikuli::KeyModifier.CTRL)
      raise e
    end
  end
  @screen.hide_cursor
  @screen.wait(          chan_image(account, channel, 'welcome'), 10)
end

Then /^I take note of the configured Pidgin accounts$/ do
  next if @skip_steps_while_restoring_background
  @persistent_pidgin_accounts = configured_pidgin_accounts
end

Then /^I take note of the OTR key for Pidgin's "([^"]+)" account$/ do |account_name|
  next if @skip_steps_while_restoring_background
  @persistent_pidgin_otr_keys = pidgin_otr_keys
end

Then /^Pidgin has the expected persistent accounts configured$/ do
  next if @skip_steps_while_restoring_background
  current_accounts = configured_pidgin_accounts
  assert(current_accounts <=> @persistent_pidgin_accounts,
         "Currently configured Pidgin accounts do not match the persistent ones:\n" +
         "Current:\n#{current_accounts}\n" +
         "Persistent:\n#{@persistent_pidgin_accounts}"
         )
end

Then /^Pidgin has the expected persistent OTR keys$/ do
  next if @skip_steps_while_restoring_background
  assert_equal(pidgin_otr_keys, @persistent_pidgin_otr_keys)
end

def pidgin_add_certificate_from (cert_file)
  # Here, we need a certificate that is not already in the NSS database
  step "I copy \"/usr/share/ca-certificates/spi-inc.org/spi-cacert-2008.crt\" to \"#{cert_file}\" as user \"amnesia\""

  @vm.focus_window('Buddy List')
  @screen.wait_and_click('PidginToolsMenu.png', 10)
  @screen.wait_and_click('PidginCertificatesMenuItem.png', 10)
  @screen.wait('PidginCertificateManagerDialog.png', 10)
  @screen.wait_and_click('PidginCertificateAddButton.png', 10)
  begin
    @screen.wait_and_click('GtkFileChooserDesktopButton.png', 10)
  rescue FindFailed
    # The first time we're run, the file chooser opens in the Recent
    # view, so we have to browse a directory before we can use the
    # "Type file name" button. But on subsequent runs, the file
    # chooser is already in the Desktop directory, so we don't need to
    # do anything. Hence, this noop exception handler.
  end
  @screen.wait_and_click('GtkFileTypeFileNameButton.png', 10)
  @screen.type("l", Sikuli::KeyModifier.ALT) # "Location" field
  @screen.type(cert_file + Sikuli::Key.ENTER)
end

Then /^I can add a certificate from the "([^"]+)" directory to Pidgin$/ do |cert_dir|
  next if @skip_steps_while_restoring_background
  pidgin_add_certificate_from("#{cert_dir}/test.crt")
  wait_and_focus('PidginCertificateAddHostnameDialog.png', 10, 'Certificate Import')
  @screen.type("XXX test XXX" + Sikuli::Key.ENTER)
  wait_and_focus('PidginCertificateTestItem.png', 10, 'Certificate Manager')
end

Then /^I cannot add a certificate from the "([^"]+)" directory to Pidgin$/ do |cert_dir|
  next if @skip_steps_while_restoring_background
  pidgin_add_certificate_from("#{cert_dir}/test.crt")
  wait_and_focus('PidginCertificateImportFailed.png', 10, 'Import Error')
end

When /^I close Pidgin's certificate manager$/ do
  wait_and_focus('PidginCertificateManagerDialog.png', 10, 'Certificate Manager')
  @screen.type(Sikuli::Key.ESC)
  # @screen.wait_and_click('PidginCertificateManagerClose.png', 10)
  @screen.waitVanish('PidginCertificateManagerDialog.png', 10)
end

When /^I close Pidgin's certificate import failure dialog$/ do
  @screen.type(Sikuli::Key.ESC)
  # @screen.wait_and_click('PidginCertificateManagerClose.png', 10)
  @screen.waitVanish('PidginCertificateImportFailed.png', 10)
end

When /^I see the Tails roadmap URL$/ do
  try_for(60) do
    begin
      @screen.find('PidginTailsRoadmapUrl.png')
    rescue FindFailed => e
      @screen.click('PidginScrollArrowUp.png')
      raise e
    end
  end
end

When /^I click on the Tails roadmap URL$/ do
  @screen.click('PidginTailsRoadmapUrl.png')
end

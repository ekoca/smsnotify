require 'rubygems'
require 'twilio-ruby'
require 'sinatra'
require 'sinatra/multi_route'
require 'sinatra/reloader' if settings.development?
require 'yaml'
require 'phony'
require 'logger'
require 'listen'
require_relative 'settings'


Dir.mkdir("#{settings.root}/log/") unless Dir.exist?("#{settings.root}/log/")
error_logger = File.new("#{settings.root}/log/application.log", 'a+')
error_logger.sync = true

if settings.production?
  @configLocation = "#{settings.root}/configs/config.prod.yml"
elsif settings.development?
  @configLocation = "#{settings.root}/configs/config.dev.yml"
end

configure do
  resLogger = Logger.new("#{settings.root}/log/application.log",)
  unless defined?(LOGGER)
    LOGGER = resLogger
  end
  Settings.load!(@configLocation)
  enable :logging, :dump_errors
  set :raise_errors, true

  listener = Listen.to(File.dirname(@configLocation)) do |modified|
    LOGGER.info "Configuration file #{modified} was modified"
    Settings.load!(@configLocation)
  end
  listener.start # not blocking
end

before do
  env["rack.errors"] = error_logger
end

get '/ping' do
  # pinger URL for newrelic
  Twilio::VERSION.to_s
end

module Helper
  # Get user name from sms phone number
  # sent inthe message
  def self.getUserFromPhone(smsPhone)
    fromuser = ''
    Settings.users.each do |user|
      if user[:phones].collect { |x| Phony.normalize(x) }.include?(smsPhone)
        fromuser = user[:name]
        break
      end
    end

    fromuser
  end


  # Get the command to execute as well as the
  # Location
  def self.getCommandObject(fromUser, smsText)
    commandStruct = Struct.new(:fromLocation, :runCommand)
    commandObj = commandStruct.new('', nil)

    Settings.responders.each do |location|
      if location[:users].include?(fromUser) == true
        commandObj[:fromLocation] = location[:name]

        location[:commands].each do |command|
          if command[:text].downcase == smsText.downcase
            commandObj[:runCommand] = command
            break
          elsif command[:text].downcase == '*' #TODO: verify that this logic is correct
            commandObj[:runCommand] = command
            break
          end
        end
      end
    end

    commandObj
  end

  # Process the generated command object. The execution can be a
  # bash/ruby/php script. Once the results are posted to Standard Out. It should be fine
  def self.handleCommandObject(commandObj, fromUser)
    if commandObj.runCommand.nil?
      twiml = Twilio::TwiML::Response.new do |r|
        r.Message "You are not authorized to use this service.  Contact support."
      end
    else
      twiml = Twilio::TwiML::Response.new do |r|
        result = Helper.runCommand(commandObj)

        if result.is_a?(Hash) && result.has_key?('message')
          if result.has_key?('reply-to-sender') && result['reply-to-sender']== true
            r.Message result['message']
          end
        end

        #r.Message "User: #{fromUser}\nLocation: #{commandObj.fromLocation}\nCommand: #{commandObj.runCommand.inspect}"
      end
    end

    twiml
  end

  # Will run the command as a sub process of this application
  # It uses the scripts interpreter directive (the command after the Shebang in the initial)
  # line of the script
  def self.runCommand(comm)
    script = comm.runCommand[:command]
    result = '{}'

    if File.executable?(script)
      fhandle = File.open(script)

      interpreterDirective =  fhandle.readline.strip.sub("#!", "")
      result = Helper.execWithInterpreterDirective("#{interpreterDirective} #{script} #{comm.runCommand[:params]}")
    else
      LOGGER.error "File with path #{script} is not an executable. Set to executable"
      raise "Error occured"
    end

    JSON.parse(result)
  end

  # Execute bash, ruby, php etc. script. As long as the intepreter directive is at the start of the
  # script,  eg. #!/usr/bin/env bash
  #
  # Expecting a well formed JSON/XML. In the format
  # {
  #   "reply-to-sender": true,
  #   "name": "stopshang",
  #   "message": "this is the text response"
  # }
  #
  def self.execWithInterpreterDirective(script)
    pObj = IO.popen("#{script}")
    LOGGER.info "Running script #{script} with pid #{pObj.pid}"
    result = pObj.gets
    pObj.close

    result
  end
end

#sms route
route :get, :post, '/sms' do

    begin
      rBody = params[:Body]
      from  = params[:From]

      unless rBody.nil? || from.nil?
        smsText  =  rBody.gsub("/[^A-Za-z0-9]/u", ' ').strip.downcase
      else
        LOGGER.error "No Parameter Body in request"
        raise "An Error Occured. Contact Support"
      end

      smsPhone = Phony.normalize(from)

      # TODO: may want to add receipent phone numbers to yaml config
      smsReceipient = params[:To]

      fromUser   = Helper.getUserFromPhone(smsPhone)
      commandObj = Helper.getCommandObject(fromUser, smsText)
      twiml      = Helper.handleCommandObject(commandObj, fromUser)
    rescue
      twiml = Twilio::TwiML::Response.new do |r|
        r.Message = "An Error Occured. Contact Support"
      end
    end


   twiml.text
end


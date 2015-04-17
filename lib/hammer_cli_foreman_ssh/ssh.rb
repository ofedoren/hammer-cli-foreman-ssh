require 'hammer_cli'
require 'hammer_cli_foreman/host'
require 'net/ssh/multi'

module HammerCLIForemanSsh
  class Command < HammerCLIForeman::Command

    DEFAULT_PER_PAGE = 1000

    resource :hosts
    action :index

    command_name 'SSH to hosts'
    option %w(-c --command), 'COMMAND', _('Command to execute'), :attribute_name => :command, :required => true
    option %w(-n --concurrent), 'CONCURRENCY', _('Number of concurrent SSH sessions'), :attribute_name => :concurrent do |o|
      Integer(o)
    end
    option %w(-u --user), 'USER', _('Execute as user'), :attribute_name => :user, :default => ENV['USER']
    option %w(-s --search), 'FILTER', _('Filter hosts based on a filter'), :attribute_name => :search
    option '--[no-]dns', :flag, _('Use DNS to resolve IP addresses'), :attribute_name => :use_dns
    option '--[no-]prompt', :flag, _('Prompt for users approval'), :attribute_name => :prompt
    option %w(-i --identity_file), 'FILE',
      _('Selects a file from which the identity (private key) for public key authentication is read'),
      :attribute_name => :identity_file

    def request_params
      params             = super
      params['search']   ||= search
      params['per_page'] ||= HammerCLI::Settings.get(:ui, :per_page) || DEFAULT_PER_PAGE
      params
    end

    def execute
      signal_usage_error(_("specify 1 or more concurrent hosts")) if (!concurrent.nil? && concurrent < 1)

      puts _("About to execute: #{command} as user #{user}\n" +
      "on the following #{hosts.size} hosts: #{host_names.join(', ')}")

      unless prompt? == false || ask(_('Continue, (y/N)')).downcase == 'y'
        warn _('aborting per user request')
        return HammerCLI::EX_OK
      end

      ssh_options = { :user => user, :auth_methods => ['publickey'] }
      ssh_options[:keys] = [identity_file] unless identity_file.to_s.empty?

      Net::SSH::Multi.start(:concurrent_connections => concurrent, :on_error => :warn) do |session|
        logger.info(_("executing on #{concurrent} concurrent host(s)")) if concurrent.to_i > 0
        targets.each { |s| session.use s, ssh_options }
        session.exec command
        session.loop
      end

      HammerCLI::EX_OK
    end

    private

    def response
      @response ||= send_request
    end

    def hosts
      @hosts ||= response['results']
    end

    def host_names
      @host_names ||= hosts.map { |h| h['name'] }
    end

    def targets
      (use_dns?.nil? || use_dns?) ? host_names : host_ips
    end

    def host_ips
      @host_ips ||= hosts.map { |h| h['ip'] }
    end

  end

  HammerCLIForeman::Host.subcommand('ssh', _('Remote execution via SSH to selected hosts'), HammerCLIForemanSsh::Command)
end

module Proxy::HostReports
  class PluginConfiguration
    def load_classes
      require "smart_proxy_host_reports/spooled_http_client"
    end

    def load_dependency_injection_wirings(container, _settings)
      container.singleton_dependency :host_reports_spool, -> {
          SpooledHttpClient.instance.initialize_directory
        }
    end
  end

  class Plugin < ::Proxy::Plugin
    plugin :host_reports, Proxy::HostReports::VERSION

    default_settings reported_proxy_hostname: "localhost",
      debug_payload: false,
      spool_dir: "/var/lib/foreman-proxy",
      keep_reports: false

    http_rackup_path File.expand_path("host_reports_http_config.ru", File.expand_path("../", __FILE__))
    https_rackup_path File.expand_path("host_reports_http_config.ru", File.expand_path("../", __FILE__))

    load_classes PluginConfiguration
    load_dependency_injection_wirings PluginConfiguration
    start_services :host_reports_spool
  end
end

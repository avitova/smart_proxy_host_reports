module Proxy::Reports
  class SpooledHttpClient
    include Proxy::Log
    include Singleton

    def spool_path(state = "temp", filename = nil)
      if filename
        File.join(@spool_dir, state, filename)
      else
        File.join(@spool_dir, state)
      end
    end

    def spool_move(from_state, to_state, filename)
      # TODO: implement fsync?
      FileUtils.mv(spool_path(from_state, filename), spool_path(to_state, filename))
    end

    def initialize
      @worker = nil
    end

    def initialize_directory(spool_dir = Proxy::Reports::Plugin.settings.spool_dir)
      raise("Setting spool_dir uninitialized") unless spool_dir
      @spool_dir = spool_dir
      ["temp", "todo", "done", "fail"].each do |state|
        FileUtils.mkdir_p(spool_path(state))
      end
      self
    end

    def start
      @worker_running = true
      @worker = Thread.new do
        while @worker_running
          begin
            logger.info "Started host reports spooled http client"
            process
          rescue StandardError => e
            logger.error "Error during spool processing: #{e}", e
          end
          Thread.stop
        end
        logger.info "Stopped host reports spooled http client"
      end
    end

    # smart proxy currently does not support stopping services
    def stop
      @worker_running = false
      wakeup
      @worker.join
    end

    def get_name(filename)
      filename[filename.rindex("-") + 1..-1]
    end

    def connect(http, factory, type, endpoint, facts_name = "*")
      processed = 0
      files = Dir.glob(spool_path("todo", "*-" + type + "-" + facts_name)).sort
      files.each do |filename|
        basename = File.basename(filename)
        logger.debug "Sending report #{basename}"
        begin
          post = factory.create_post(endpoint, File.read(filename))
          response = http.request(post)
          logger.info "Report #{basename} sent with HTTP response #{response.code}"
          logger.debug { "Response body: #{response.body}" }
          if response.code.start_with?("2")
            if Proxy::Reports::Plugin.settings.keep_reports
              spool_move("todo", "done", basename)
            else
              FileUtils.rm_f spool_path("todo", basename)
            end
          else
            logger.debug { "Moving failed report to 'fail' spool directory" }
            spool_move("todo", "done", basename)
          end
          processed += 1
        rescue StandardError => e
          logger.warn "Unable to send #{basename}, will try on next request: #{e}", e
          raise if ENV["RACK_ENV"] == "test"
        end
      if type == "report"
        processed += connect(http, factory, "facts", "/api/v2/hosts/facts", basename)
      end
      end
      processed
    end

    def process
      processed = 0
      client = ::Proxy::HttpRequest::ForemanRequest.new
      factory = client.request_factory
      # send all files via a single persistent HTTP connection
      logger.debug "Opening HTTP connection to Foreman"
      client.http.start do |http|
        processed += connect(http, factory, "report", "/api/v2/host_reports")
        processed += connect(http, factory, "facts", "/api/v2/hosts/facts")
      end
      logger.debug "Finished uploading #{processed} reports, closing connection"
    end

    def wakeup
      @worker.wakeup if @worker
    end

    def time_padding(time)
      integral = (time.to_i).to_s
      fraction = (time % 1).to_s[2..-1]
      integral.rjust(10, "0") + "." + fraction.rjust(10, "0")
    end

    def spool(prefix, filename, data)
      time = time_padding(Process.clock_gettime(Process::CLOCK_MONOTONIC))
      filename = time + "-" + prefix + "-" + filename.gsub(/[^0-9a-z]/i, "")
      file = spool_path("temp", filename)
      File.open(file, "w") { |f| f.write(data) }
      spool_move("temp", "todo", filename)
      wakeup
    end
  end
end

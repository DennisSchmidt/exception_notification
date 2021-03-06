module ExceptionNotifier
  class SlackNotifier < BaseNotifier
    include ExceptionNotifier::BacktraceCleaner

    attr_accessor :notifier

    def initialize(options)
      super
      begin
        @ignore_data_if = options[:ignore_data_if]
        @backtrace_lines = options[:backtrace_lines]

        webhook_url = options.fetch(:webhook_url)
        @message_opts = options.fetch(:additional_parameters, {})
        @color = @message_opts.delete(:color) { 'danger' }
        @notifier = Slack::Notifier.new webhook_url, options
      rescue
        @notifier = nil
      end
    end

    def call(exception, options={})
      text = text(exception, options)
      clean_message = exception.message.gsub("`", "'")

      fields = [
        { title: 'Exception', value: clean_message },
        { title: 'Hostname', value: Socket.gethostname },
        { title: 'Occurred at', value: Time.now.utc.iso8601(3) }
      ]

      fields.push({ title: 'Backtrace', value: formatted_backtrace(exception) }) if exception.backtrace

      if (data = additional_data(options)).present?
        data_string = data.map{|k,v| "#{k}: #{v}"}.join("\n")
        fields.push({ title: 'Data', value: "```#{data_string}```" })
      end

      attchs = [color: @color, text: text, fields: fields, mrkdwn_in: %w(text fields)]

      if valid?
        send_notice(exception, options, clean_message, @message_opts.merge(attachments: attchs)) do |msg, message_opts|
          @notifier.ping '', message_opts
        end
      end
    end

    protected

    def text(exception, options)
      exception_name = exception_name(exception, options[:accumulated_errors_count].to_i)

      text = "*At* `#{Time.now.utc.iso8601(3)}`"

      if options[:env].nil?
        text +=" #{exception_name} *occured in background*\n"
      else
        env = options[:env]
        kontroller = env['action_controller.instance']
        request = "#{env['REQUEST_METHOD']} <#{env['REQUEST_URI']}>"

        text += " #{exception_name} *occurred while* `#{request}`"
        text += " *was processed by* `#{kontroller.controller_name}##{kontroller.action_name}`" if kontroller
        text += "\n"
      end

      text
    end

    def exception_name(exception, errors_count)
      measure_word = errors_count > 1 ? errors_count : (exception.class.to_s =~ /^[aeiou]/i ? 'an' : 'a')
      "*#{measure_word}* `#{exception.class.to_s}`"
    end

    def formatted_backtrace(exception)
      @backtrace_lines ? "```#{exception.backtrace.first(@backtrace_lines).join("\n")}```" : "```#{exception.backtrace.join("\n")}```"
    end

    def additional_data(options)
      data = options[:data] || {}
      if options[:env]
        data = (options[:env]['exception_notifier.exception_data'] || {}).merge(data)
      end

      deep_reject(data, @ignore_data_if) if @ignore_data_if.is_a?(Proc)

      data
    end

    def valid?
      !@notifier.nil?
    end

    def deep_reject(hash, block)
      hash.each do |k, v|
        if v.is_a?(Hash)
          deep_reject(v, block)
        end

        if block.call(k, v)
          hash.delete(k)
        end
      end
    end

  end
end

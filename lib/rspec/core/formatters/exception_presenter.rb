module RSpec
  module Core
    module Formatters
      # @private
      class ExceptionPresenter
        attr_reader :exception, :example, :description, :message_color,
                    :detail_formatter, :extra_detail_formatter, :backtrace_formatter
        private :message_color, :detail_formatter, :extra_detail_formatter, :backtrace_formatter

        def initialize(exception, example, options={})
          @exception               = exception
          @example                 = example
          @message_color           = options.fetch(:message_color)          { RSpec.configuration.failure_color }
          @description             = options.fetch(:description_formatter)  { Proc.new { example.full_description } }.call(self)
          @detail_formatter        = options.fetch(:detail_formatter)       { Proc.new {} }
          @extra_detail_formatter  = options.fetch(:extra_detail_formatter) { Proc.new {} }
          @backtrace_formatter     = options.fetch(:backtrace_formatter)    { RSpec.configuration.backtrace_formatter }
          @indentation             = options.fetch(:indentation, 2)
          @skip_shared_group_trace = options.fetch(:skip_shared_group_trace, false)
          @failure_lines           = options[:failure_lines]
        end

        def message_lines
          add_shared_group_lines(failure_lines, Notifications::NullColorizer)
        end

        def colorized_message_lines(colorizer=::RSpec::Core::Formatters::ConsoleCodes)
          add_shared_group_lines(failure_lines, colorizer).map do |line|
            colorizer.wrap line, message_color
          end
        end

        def formatted_backtrace
          backtrace_formatter.format_backtrace(exception.backtrace, example.metadata)
        end

        def colorized_formatted_backtrace(colorizer=::RSpec::Core::Formatters::ConsoleCodes)
          formatted_backtrace.map do |backtrace_info|
            colorizer.wrap "# #{backtrace_info}", RSpec.configuration.detail_color
          end
        end

        def fully_formatted(failure_number, colorizer=::RSpec::Core::Formatters::ConsoleCodes)
          alignment_basis = "#{' ' * @indentation}#{failure_number}) "
          indentation = ' ' * alignment_basis.length

          "\n#{alignment_basis}#{description_and_detail(colorizer, indentation)}" \
          "\n#{formatted_message_and_backtrace(colorizer, indentation)}" \
          "#{extra_detail_formatter.call(failure_number, colorizer, indentation)}"
        end

        def failure_slash_error_line
          @failure_slash_error_line ||= "Failure/Error: #{read_failed_line.strip}"
        end

      private

        def description_and_detail(colorizer, indentation)
          detail = detail_formatter.call(example, colorizer, indentation)
          return (description || detail) unless description && detail
          "#{description}\n#{indentation}#{detail}"
        end

        if String.method_defined?(:encoding)
          def encoding_of(string)
            string.encoding
          end

          def encoded_string(string)
            RSpec::Support::EncodedString.new(string, Encoding.default_external)
          end
        else # for 1.8.7
          # :nocov:
          def encoding_of(_string)
          end

          def encoded_string(string)
            RSpec::Support::EncodedString.new(string)
          end
          # :nocov:
        end

        def exception_class_name
          name = exception.class.name.to_s
          name = "(anonymous error class)" if name == ''
          name
        end

        def failure_lines
          @failure_lines ||=
            begin
              lines = []
              lines << failure_slash_error_line unless (description == failure_slash_error_line)
              lines << "#{exception_class_name}:" unless exception_class_name =~ /RSpec/
              encoded_string(exception.message.to_s).split("\n").each do |line|
                lines << "  #{line}"
              end
              lines
            end
        end

        def add_shared_group_lines(lines, colorizer)
          return lines if @skip_shared_group_trace

          example.metadata[:shared_group_inclusion_backtrace].each do |frame|
            lines << colorizer.wrap(frame.description, RSpec.configuration.default_color)
          end

          lines
        end

        def read_failed_line
          matching_line = find_failed_line
          unless matching_line
            return "Unable to find matching line from backtrace"
          end

          file_path, line_number = matching_line.match(/(.+?):(\d+)(|:\d+)/)[1..2]

          if File.exist?(file_path)
            File.readlines(file_path)[line_number.to_i - 1] ||
              "Unable to find matching line in #{file_path}"
          else
            "Unable to find #{file_path} to read failed line"
          end
        rescue SecurityError
          "Unable to read failed line"
        end

        def find_failed_line
          example_path = example.metadata[:absolute_file_path].downcase
          exception.backtrace.find do |line|
            next unless (line_path = line[/(.+?):(\d+)(|:\d+)/, 1])
            File.expand_path(line_path).downcase == example_path
          end
        end

        def formatted_message_and_backtrace(colorizer, indentation)
          lines = colorized_message_lines(colorizer) + colorized_formatted_backtrace(colorizer)

          formatted = ""

          lines.each do |line|
            formatted << RSpec::Support::EncodedString.new("#{indentation}#{line}\n", encoding_of(formatted))
          end

          formatted
        end

        # @private
        # Configuring the `ExceptionPresenter` with the right set of options to handle
        # pending vs failed vs skipped and aggregated (or not) failures is not simple.
        # This class takes care of building an appropriate `ExceptionPresenter` for the
        # provided example.
        class Factory
          def build
            ExceptionPresenter.new(@exception, @example, options)
          end

        private

          def initialize(example)
            @example          = example
            @execution_result = example.execution_result
            @exception        = if @execution_result.status == :pending
                                  @execution_result.pending_exception
                                else
                                  @execution_result.exception
                                end
          end

          def options
            with_multiple_error_options_as_needed(@exception, pending_options || {})
          end

          def pending_options
            if @execution_result.pending_fixed?
              {
                :description_formatter => Proc.new { "#{@example.full_description} FIXED" },
                :message_color         => RSpec.configuration.fixed_color,
                :failure_lines         => [
                  "Expected pending '#{@execution_result.pending_message}' to fail. No Error was raised."
                ]
              }
            elsif @execution_result.status == :pending
              {
                :message_color    => RSpec.configuration.pending_color,
                :detail_formatter => PENDING_DETAIL_FORMATTER
              }
            end
          end

          def with_multiple_error_options_as_needed(exception, options)
            return options unless multiple_exceptions_not_met_error?(exception)

            options = options.merge(
              :failure_lines          => [],
              :extra_detail_formatter => sub_failure_list_formatter(exception, options[:message_color]),
              :detail_formatter       => multiple_failure_sumarizer(exception,
                                                                    options[:detail_formatter],
                                                                    options[:message_color])
            )

            options[:description_formatter] &&= Proc.new {}

            return options unless exception.aggregation_metadata[:from_around_hook]
            options[:backtrace_formatter] = EmptyBacktraceFormatter
            options
          end

          def multiple_exceptions_not_met_error?(exception)
            return false unless defined?(RSpec::Expectations::MultipleExpectationsNotMetError)
            RSpec::Expectations::MultipleExpectationsNotMetError === exception
          end

          def multiple_failure_sumarizer(exception, prior_detail_formatter, color)
            lambda do |example, colorizer, indentation|
              summary = if exception.aggregation_metadata[:from_around_hook]
                          "Got #{exception.exception_count_description}:"
                        else
                          "#{exception.summary}."
                        end

              summary = colorizer.wrap(summary, color || RSpec.configuration.failure_color)
              return summary unless prior_detail_formatter
              "#{prior_detail_formatter.call(example, colorizer, indentation)}\n#{indentation}#{summary}"
            end
          end

          def sub_failure_list_formatter(exception, message_color)
            common_backtrace_truncater = CommonBacktraceTruncater.new(exception)

            lambda do |failure_number, colorizer, indentation|
              exception.all_exceptions.each_with_index.map do |failure, index|
                options = with_multiple_error_options_as_needed(
                  failure,
                  :description_formatter   => :failure_slash_error_line.to_proc,
                  :indentation             => indentation.length,
                  :message_color           => message_color || RSpec.configuration.failure_color,
                  :skip_shared_group_trace => true
                )

                failure   = common_backtrace_truncater.with_truncated_backtrace(failure)
                presenter = ExceptionPresenter.new(failure, @example, options)
                presenter.fully_formatted("#{failure_number}.#{index + 1}", colorizer)
              end.join
            end
          end

          # @private
          # Used to prevent a confusing backtrace from showing up from the `aggregate_failures`
          # block declared for `:aggregate_failures` metadata.
          module EmptyBacktraceFormatter
            def self.format_backtrace(*)
              []
            end
          end

          # @private
          class CommonBacktraceTruncater
            def initialize(parent)
              @parent = parent
            end

            def with_truncated_backtrace(child)
              child_bt  = child.backtrace
              parent_bt = @parent.backtrace
              return child if child_bt.nil? || child_bt.empty? || parent_bt.nil?

              index_before_first_common_frame = -1.downto(-child_bt.size).find do |index|
                parent_bt[index] != child_bt[index]
              end

              return child if index_before_first_common_frame == -1

              child = child.dup
              child.set_backtrace(child_bt[0..index_before_first_common_frame])
              child
            end
          end
        end

        # @private
        PENDING_DETAIL_FORMATTER = Proc.new do |example, colorizer|
          colorizer.wrap("# #{example.execution_result.pending_message}", :detail)
        end
      end
    end
  end
end

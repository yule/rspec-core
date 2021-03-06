require 'pathname'

module RSpec::Core
  RSpec.describe Formatters::ExceptionPresenter do
    include FormatterSupport

    let(:example) { new_example }
    let(:presenter) { Formatters::ExceptionPresenter.new(exception, example) }

    before do
      allow(example.execution_result).to receive(:exception) { exception }
      example.metadata[:absolute_file_path] = __FILE__
    end

    describe "#fully_formatted" do
      line_num = __LINE__ + 2
      let(:exception) { instance_double(Exception, :message => "Boom\nBam", :backtrace => [ "#{__FILE__}:#{line_num}"]) }
      # The failure happened here!

      it "formats the exception with all the normal details" do
        expect(presenter.fully_formatted(1)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |  1) Example
          |     Failure/Error: # The failure happened here!
          |       Boom
          |       Bam
          |     # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
        EOS
      end

      it "indents properly when given a multiple-digit failure index" do
        expect(presenter.fully_formatted(100)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |  100) Example
          |       Failure/Error: # The failure happened here!
          |         Boom
          |         Bam
          |       # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
        EOS
      end

      it "allows the caller to specify additional indentation" do
        presenter = Formatters::ExceptionPresenter.new(exception, example, :indentation => 4)

        expect(presenter.fully_formatted(1)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |    1) Example
          |       Failure/Error: # The failure happened here!
          |         Boom
          |         Bam
          |       # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
        EOS
      end

      it 'passes the indentation on to the `:detail_formatter` lambda so it can align things' do
        detail_formatter = Proc.new { "Some Detail" }

        presenter = Formatters::ExceptionPresenter.new(exception, example, :indentation => 4,
                                                       :detail_formatter => detail_formatter)
        expect(presenter.fully_formatted(1)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |    1) Example
          |       Some Detail
          |       Failure/Error: # The failure happened here!
          |         Boom
          |         Bam
          |       # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
        EOS
      end

      it 'allows the caller to omit the description' do
        presenter = Formatters::ExceptionPresenter.new(exception, example,
                                                       :detail_formatter => Proc.new { "Detail!" },
                                                       :description_formatter => Proc.new { })

        expect(presenter.fully_formatted(1)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |  1) Detail!
          |     Failure/Error: # The failure happened here!
          |       Boom
          |       Bam
          |     # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
        EOS
      end

      it 'allows the failure/error line to be used as the description' do
        presenter = Formatters::ExceptionPresenter.new(exception, example, :description_formatter => lambda { |p| p.failure_slash_error_line })

        expect(presenter.fully_formatted(1)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |  1) Failure/Error: # The failure happened here!
          |       Boom
          |       Bam
          |     # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
        EOS
      end

      it 'allows a caller to specify extra details that are added to the bottom' do
        presenter = Formatters::ExceptionPresenter.new(
          exception, example, :extra_detail_formatter => lambda do |failure_number, colorizer, indentation|
            "#{indentation}extra detail for failure: #{failure_number}\n"
          end
        )

        expect(presenter.fully_formatted(2)).to eq(<<-EOS.gsub(/^ +\|/, ''))
          |
          |  2) Example
          |     Failure/Error: # The failure happened here!
          |       Boom
          |       Bam
          |     # ./spec/rspec/core/formatters/exception_presenter_spec.rb:#{line_num}
          |     extra detail for failure: 2
        EOS
      end
    end

    describe "#read_failed_line" do
      def read_failed_line
        presenter.send(:read_failed_line)
      end

      context "when backtrace is a heterogeneous language stack trace" do
        let(:exception) do
          instance_double(Exception, :backtrace => [
            "at Object.prototypeMethod (foo:331:18)",
            "at Array.forEach (native)",
            "at a_named_javascript_function (/some/javascript/file.js:39:5)",
            "/some/line/of/ruby.rb:14"
          ])
        end

        it "is handled gracefully" do
          expect { read_failed_line }.not_to raise_error
        end
      end

      context "when backtrace will generate a security error" do
        let(:exception) { instance_double(Exception, :backtrace => [ "#{__FILE__}:#{__LINE__}"]) }

        it "is handled gracefully" do
          with_safe_set_to_level_that_triggers_security_errors do
            expect { read_failed_line }.not_to raise_error
          end
        end
      end

      context "when ruby reports a bogus line number in the stack trace" do
        let(:exception) { instance_double(Exception, :backtrace => [ "#{__FILE__}:10000000"]) }

        it "reports the filename and that it was unable to find the matching line" do
          expect(read_failed_line).to include("Unable to find matching line")
        end
      end

      context "when ruby reports a file that does not exist" do
        let(:file) { "#{__FILE__}/blah.rb" }
        let(:exception) { instance_double(Exception, :backtrace => [ "#{file}:1"]) }

        it "reports the filename and that it was unable to find the matching line" do
          example.metadata[:absolute_file_path] = file
          expect(read_failed_line).to include("Unable to find #{file} to read failed line")
        end
      end

      context "when the stacktrace includes relative paths (which can happen when using `rspec/autorun` and running files through `ruby`)" do
        let(:relative_file) { Pathname(__FILE__).relative_path_from(Pathname(Dir.pwd)) }
        line = __LINE__
        let(:exception) { instance_double(Exception, :backtrace => ["#{relative_file}:#{line}"]) }

        it 'still finds the backtrace line' do
          expect(read_failed_line).to include("line = __LINE__")
        end
      end

      context "when String alias to_int to_i" do
        before do
          String.class_exec do
            alias :to_int :to_i
          end
        end

        after do
          String.class_exec do
            undef to_int
          end
        end

        let(:exception) { instance_double(Exception, :backtrace => [ "#{__FILE__}:#{__LINE__}"]) }

        it "doesn't hang when file exists" do
          expect(read_failed_line.strip).to eql(
            %Q[let(:exception) { instance_double(Exception, :backtrace => [ "\#{__FILE__}:\#{__LINE__}"]) }])
        end
      end
    end
  end

  RSpec.describe Formatters::ExceptionPresenter::Factory::CommonBacktraceTruncater do
    def truncate(parent, child)
      described_class.new(parent).with_truncated_backtrace(child)
    end

    def exception_with(backtrace)
      exception = Exception.new
      exception.set_backtrace(backtrace)
      exception
    end

    it 'returns an exception with the common part truncated' do
      parent = exception_with %w[ foo.rb:1 bar.rb:2 car.rb:7 ]
      child  = exception_with %w[ file_1.rb:3 file_1.rb:9 foo.rb:1 bar.rb:2 car.rb:7 ]

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to eq %w[ file_1.rb:3 file_1.rb:9 ]
    end

    it 'ignores excess lines in the top of the parent trace that the child does not have' do
      parent = exception_with %w[ foo.rb:1 foo.rb:2 foo.rb:3 bar.rb:2 car.rb:7 ]
      child  = exception_with %w[ file_1.rb:3 file_1.rb:9 bar.rb:2 car.rb:7 ]

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to eq %w[ file_1.rb:3 file_1.rb:9 ]
    end

    it 'does not truncate anything if the parent has excess lines at the bottom of the trace' do
      parent = exception_with %w[ foo.rb:1 bar.rb:2 car.rb:7 bazz.rb:9 ]
      child  = exception_with %w[ file_1.rb:3 file_1.rb:9 foo.rb:1 bar.rb:2 car.rb:7 ]

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to eq %w[ file_1.rb:3 file_1.rb:9 foo.rb:1 bar.rb:2 car.rb:7 ]
    end

    it 'does not mutate the provided exception' do
      parent = exception_with %w[ foo.rb:1 bar.rb:2 car.rb:7 ]
      child  = exception_with %w[ file_1.rb:3 file_1.rb:9 foo.rb:1 bar.rb:2 car.rb:7 ]

      expect { truncate(parent, child) }.not_to change(child, :backtrace)
    end

    it 'returns an exception with all the same attributes (except backtrace) as the provided one' do
      parent = exception_with %w[ foo.rb:1 bar.rb:2 car.rb:7 ]

      my_custom_exception_class = Class.new(StandardError) do
        attr_accessor :foo, :bar
      end

      child = my_custom_exception_class.new("Some Message")
      child.foo = 13
      child.bar = 20
      child.set_backtrace(%w[ foo.rb:1 ])

      truncated = truncate(parent, child)

      expect(truncated).to have_attributes(
        :message => "Some Message",
        :foo => 13,
        :bar => 20
      )
    end

    it 'handles child exceptions that have a blank array for the backtrace' do
      parent = exception_with %w[ foo.rb:1 bar.rb:2 car.rb:7 ]
      child  = exception_with %w[ ]

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to eq %w[ ]
    end

    it 'handles child exceptions that have `nil` for the backtrace' do
      parent = exception_with %w[ foo.rb:1 bar.rb:2 car.rb:7 ]
      child  = Exception.new

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to be_nil
    end

    it 'handles parent exceptions that have a blank array for the backtrace' do
      parent = exception_with %w[ ]
      child  = exception_with %w[ foo.rb:1 ]

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to eq %w[ foo.rb:1 ]
    end

    it 'handles parent exceptions that have `nil` for the backtrace' do
      parent = Exception.new
      child  = exception_with %w[ foo.rb:1 ]

      truncated = truncate(parent, child)

      expect(truncated.backtrace).to eq %w[ foo.rb:1 ]
    end

    it 'returns the original exception object (not a dup) when there is no need to update the backtrace' do
      parent = exception_with %w[ bar.rb:1 ]
      child  = exception_with %w[ foo.rb:1 ]

      truncated = truncate(parent, child)

      expect(truncated).to be child
    end
  end
end

require 'rspec/core/ast/node'
require 'ripper'

module RSpec::Core::AST
  RSpec.describe Node do
    let(:root_node) do
      Node.new(sexp)
    end

    let(:sexp) do
      Ripper.sexp(source)
    end

    let(:source) { <<-END }
      variable = do_something(1, 2)
      variable.do_anything do |arg|
        puts arg
      end
    END

    # [:program,
    #  [[:assign,
    #    [:var_field, [:@ident, "variable", [1, 6]]],
    #    [:method_add_arg,
    #     [:fcall, [:@ident, "do_something", [1, 17]]],
    #     [:arg_paren,
    #      [:args_add_block,
    #       [[:@int, "1", [1, 30]], [:@int, "2", [1, 33]]],
    #       false]]]],
    #   [:method_add_block,
    #    [:call,
    #     [:var_ref, [:@ident, "variable", [2, 6]]],
    #     :".",
    #     [:@ident, "do_anything", [2, 15]]],
    #    [:do_block,
    #     [:block_var,
    #      [:params, [[:@ident, "arg", [2, 31]]], nil, nil, nil, nil, nil, nil],
    #      false],
    #     [[:command,
    #       [:@ident, "puts", [3, 8]],
    #       [:args_add_block, [[:var_ref, [:@ident, "arg", [3, 13]]]], false]]]]]]]

    describe '#args' do
      context 'when the sexp args consist of direct child sexps' do
        let(:node) do
          root_node.each_node.find { |node| node.type == :method_add_arg }
        end

        it 'returns the child nodes' do
          expect(node.args).to match([
            an_object_having_attributes(type: :fcall),
            an_object_having_attributes(type: :arg_paren)
          ])
        end
      end

      context 'when the sexp args include an array of sexps' do
        let(:node) do
          root_node.each_node.find { |node| node.type == :args_add_block }
        end

        it 'returns pseudo group node for the array' do
          expect(node.args).to match([
            an_object_having_attributes(type: :group),
            false
          ])
        end
      end
    end

    describe '#location' do
      context 'with token node' do
        let(:node) do
          root_node.each_node.find { |node| node.type == :@ident }
        end

        it 'returns a Location object with line and column numbers' do
          expect(node.location).to have_attributes(line: 1, column: 6)
        end
      end

      context 'with non-token node' do
        let(:node) do
          root_node.each_node.find { |node| node.type == :assign }
        end

        it 'returns nil' do
          expect(node.location).to be_nil
        end
      end
    end
  end
end

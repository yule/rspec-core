module RSpec
  module Core
    module AST
      Location = Struct.new(:line, :column)

      class Node
        attr_reader :sexp, :parent

        def self.sexp?(array)
          array.is_a?(Array) && array.first.is_a?(Symbol)
        end

        def initialize(sexp, parent = nil)
          @sexp = sexp
          @parent = parent
        end

        def type
          sexp[0]
        end

        def args
          @args ||= raw_args.map do |raw_arg|
            if Node.sexp?(raw_arg)
              Node.new(raw_arg, self)
            elsif raw_arg.is_a?(Array)
              if raw_arg.size == 2 && raw_arg.all? { |e| e.is_a?(Integer) }
                Location.new(*raw_arg)
              else
                GroupNode.new(raw_arg, self)
              end
            else
              raw_arg
            end
          end
        end

        def children
          @children ||= args.select { |arg| arg.is_a?(Node) }
        end

        def each_node(&block)
          return to_enum(__method__) unless block_given?

          yield self

          children.each do |child|
            child.each_node(&block)
          end
        end

        def each_ancestor
          last_node = self

          while (current_node = last_node.parent)
            yield current_node
            last_node = current_node
          end
        end

        def location
          args.find { |arg| arg.is_a?(Location) }
        end

        def inspect
          "<#{self.class} #{type}>"
        end

        private

        def raw_args
          sexp[1..-1] || []
        end
      end

      class GroupNode < Node
        def type
          :group
        end

        private

        def raw_args
          sexp
        end
      end
    end
  end
end

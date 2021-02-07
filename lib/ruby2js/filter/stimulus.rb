#
require 'ruby2js'

module Ruby2JS
  module Filter
    module Stimulus
      include SEXP
      extend  SEXP

      STIMULUS_IMPORT = s(:import,
        [s(:pair, s(:sym, :as), s(:str, "*")),
          s(:pair, s(:sym, :from), s(:str, "stimulus"))],
          s(:const, nil, :Stimulus))

      # Example conversion
      #  before:
      #    (class (const nil :Foo) (const nil :React) nil)
      #  after:
      #    (casgn nil :foo, (send :React :createClass (hash (sym :displayName)
      #       (:str, "Foo"))))
      def on_class(node)
        cname, inheritance, *body = node.children
        return super unless cname.children.first == nil
        return super unless inheritance == s(:const, nil, :Stimulus) or
          inheritance == s(:const, s(:const, nil, :Stimulus), :Controller) or
          inheritance == s(:send, s(:const, nil, :Stimulus), :Controller)

        if inheritance == s(:const, nil, :Stimulus)
          node = node.updated(nil, [node.children.first,
            s(:const, s(:const, nil, :Stimulus), :Controller),
            *node.children[2..-1]])
        end

        @stim_targets = Set.new
        @stim_values = Set.new
        @stim_classes = Set.new
        stim_walk(node)

        prepend_list << STIMULUS_IMPORT

        nodes = node.children[2..-1]
        if nodes.length == 1 and nodes.first.type == :begin
          nodes = nodes.first.children.dup
        end

        unless @stim_classes.empty?
          classes = nodes.find_index {|child| 
            child.type == :send and child.children[0..1] == [s(:self), :classes=]
          }

          if classes == nil
            nodes.unshift s(:send, s(:self), :classes=, s(:array, *@stim_classes))
          elsif nodes[classes].children[2].type == :array
            @stim_classes.merge(nodes[classes].children[2].children)
            nodes[classes] = nodes[classes].updated(nil,
              [*nodes[classes].children[0..1], s(:array, *@stim_classes)])
          end
        end

        unless @stim_values.empty?
          values = nodes.find_index {|child| 
            child.type == :send and child.children[0..1] == [s(:self), :values=]
          }

          if values == nil
            nodes.unshift s(:send, s(:self), :values=, s(:hash,
            *@stim_values.map {|name| s(:pair, name, s(:const, nil, :String))}))
          elsif nodes[values].children[2].type == :hash
            stim_values = @stim_values.map {|name| 
              [s(:sym, name.children.first.to_sym), s(:const, nil, :String)]
            }.to_h.merge(
              nodes[values].children[2].children.map {|pair| pair.children}.to_h
            )

            nodes[values] = nodes[values].updated(nil,
              [*nodes[values].children[0..1], s(:hash,
              *stim_values.map{|name, value| s(:pair, name, value)})])
          end
        end

        unless @stim_targets.empty?
          targets = nodes.find_index {|child| 
            child.type == :send and child.children[0..1] == [s(:self), :targets=]
          }

          if targets == nil
            nodes.unshift s(:send, s(:self), :targets=, s(:array, *@stim_targets))
          elsif nodes[targets].children[2].type == :array
            @stim_targets.merge(nodes[targets].children[2].children)
            nodes[targets] = nodes[targets].updated(nil,
              [*nodes[targets].children[0..1], s(:array, *@stim_targets)])
          end
        end

        props = [:element, :application]

        props += @stim_targets.map do |name|
          name = name.children.first
          ["#{name}Target", "#{name}Targets", "has#{name[0].upcase}#{name[1..-1]}Target"]
        end

        props += @stim_values.map do |name|
          name = name.children.first
          ["#{name}Value", "has#{name[0].upcase}#{name[1..-1]}Value"]
        end

        props += @stim_classes.map do |name|
          name = name.children.first
          ["#{name}Class", "has#{name[0].upcase}#{name[1..-1]}Class"]
        end

        props = props.flatten.map {|prop| [prop.to_sym, s(:self)]}.to_h

        props[:initialize] = s(:autobind, s(:self))

        nodes.unshift s(:defineProps, props)

        node.updated(nil, [*node.children[0..1], s(:begin, *nodes)])
      end

      # analyze ivar usage
      def stim_walk(node)
        node.children.each do |child|
          next unless Parser::AST::Node === child
          stim_walk(child)

          if child.type == :send and child.children.length == 2 and
            [nil, s(:self), s(:send, nil, :this)].include? child.children[0]

            if child.children[1] =~ /^(\w+)Targets?$/
              @stim_targets.add s(:str, $1)
            elsif child.children[1] =~ /^(\w+)Value$/
              @stim_values.add s(:str, $1)
            elsif child.children[1] =~ /^(\w+)Class$/
              @stim_classes.add s(:str, $1)
            elsif child.children[1] =~ /^has([A-Z]\w*)(Target|Value|Class)$/
              name = s(:str, $1[0].downcase + $1[1..-1])
              @stim_targets.add name if $2 == 'Target'
              @stim_values.add name if $2 == 'Value'
              @stim_classes.add name if $2 == 'Class'
            end
          end

        end
      end
    end

    DEFAULTS.push Stimulus
  end
end

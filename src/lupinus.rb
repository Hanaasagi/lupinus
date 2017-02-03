# -*-coding:UTF-8-*-
require "cgi"


module StringExtensions
  refine String do
    # add the patch that can strip other chars
    def strip(chars=nil)
      if chars
        chars = Regexp.escape(chars)
        self.gsub(/\A[#{chars}]+|[#{chars}]+\z/, "")
      else
        super()
      end
    end

    def rstrip(chars=nil)
      if chars
        chars = Regexp.escape(chars)
        self.gsub(/[#{chars}]+\z/, "")
      else
        super()
      end
    end

    def lstrip(chars=nil)
      if chars
        chars = Regexp.escape(chars)
        self.gsub(/\A[#{chars}]/, "")
      else
        super()
      end
    end

  end
end


class Lupinus

  using StringExtensions

  $DEFAULT_DELIMITERS = ["{{", "}}"]
  $EMPTYSTRING = ""
  $WHITESPACE = " \t\r\b\f\v"

  $re_space = Regexp.new("[" + $WHITESPACE + "]*(\n|$)")
  $re_tag = Regexp.new(format('%s([;#/!>r{]?)\s*(.*?)\s*([}]?)%s', *$DEFAULT_DELIMITERS),
                       Regexp::MULTILINE)
  $re_indent = Regexp.new('(^|\n)(?=.|\n)', Regexp::MULTILINE)

  $filters = {}
  $filters['upcase'] = lambda {|s| s.upcase}
  $filters['downcase'] = lambda {|s| s.downcase}
  $filters['capitalize'] = lambda {|s| s.capitalize}


  # instantiate an instance of this class and call `render` with passed args
  #
  # @param see `render` doc
  # @return [String] : rendered template
  def self.render(template, context, partials={}, delimiters=$DEFAULT_DELIMITERS)
    $DEFAULT_DELIMITERS = delimiters
    new.render(template, context, partials)
  end

  # push the context to stack and call `Template::render`
  #
  # @param  [String] template : template text
  # @param  [Hash]   context  : Hash type data, e.g. {:name=>"ruby"}
  # @param  [Hash]   partials : the extern template to include, e.g. {:header=>"{{title}}\n{{charaset}}"}
  # @return [String]          : rendered template
  def render(template, context, partials)
    contexts = [context]

    if not partials.instance_of? Hash
      raise TypeError, 'partials must be Hash type'
    end

    Template::render(template, contexts, partials)
  end

  ##################################################
  ############      Template Class      ############
  ##################################################
  class Template

    # parse the template and render
    # 
    # @param  [String] template : template text
    # @param  [Array]  contexts : an Array contain Hash type data, e.g. [{:name=>"Ruby"}]
    # @param  [Hash]   partials : extern template
    # @return [String]          : rendered template
    def self.render(template, contexts, partials)
      root = parse(template)
      root.render(contexts, partials)
    end

    # standalone means a line that the tag 'left and right is blank
    #
    # @param  [String]  text  : template text
    # @param  [Integer] start : the tag start index
    # @param  [Integer] end_  : the tag end index
    # @return [Array]         : the line start position and end position
    def self.standalone?(text, start, end_)
      left = true
      right = text.match($re_space, end_)

      while (start = start - 1) >= 0
        if $WHITESPACE.include? text[start]
          next
        elsif text[start] == "\n"
          break
        else
          left = false
          break
        end
      end

      if left && right
        return start + 1, right.end(0)
      end
    end

    # parse the template and generate the syntax tree
    #
    # @param  [String] template : template text
    # @return [Root]            ： the root of syntax tree
    def self.parse(template)

      tokens = []
      index = 0
      sections = []
      tokens_stack = []
      delimiters=$DEFAULT_DELIMITERS

      root = Root.new "root"

      while (m = $re_tag.match(template, index))
        token = nil
        last_literal = nil
        strip_space = false
        # puts m.begin(0)
        if m.begin(0) > index
          # print "-" * 10 + template[index..m.begin(0)-1], "-" * 10, "\n"
          last_literal = Literal.new("str", template[index..m.begin(0)-1], root=root)
          tokens << last_literal
        end

        # {{[prefix] [name] [suffix]}}
        prefix, name, suffix = m.captures()

        if prefix == "" && suffix == ""
          # {{ name }}
          token = Variable.new(name, name, root=root)
          token.escape = true
          tokens << token

        elsif prefix == "r"
          # {{r name }}
          token = Variable.new(name, name, root=root)
          token.escape = false
          tokens << token

        elsif prefix == ";"
          # {{; comment }}
          token = Comment.new(name, root=root)
          if sections.length <= 0
            strip_space = true
          end
          tokens << token

        elsif prefix == ">"
          # {{> partial }}
          token = Partial.new(name, name, root=root)
          strip_space = true
          # get the offset of the line where the tag is located
          pos = standalone?(template, m.begin(0), m.end(0))
          if pos
            token.indent = template[pos[0]..m.begin(0)].length - 1
          end
          tokens << token

        elsif prefix == "#" || prefix == "!"
          sec_name = name.split("|")[0].strip
          if prefix == "#"
            token = Section.new(sec_name, name, root=root)
          else
            token = Inverted.new(name, name, root=root)
          end

          tokens << token
          tokens_stack << tokens

          tokens = []

          sections << [sec_name, prefix, m.end(0)]
          strip_space = true

        elsif prefix == "/"
          tag_name, sec_type, text_end = sections.pop
          if tag_name != name
            raise SyntaxError, "Tag is not matched"
          end

          child, tokens = tokens, tokens_stack.pop()

          tokens[-1].child = child
          strip_space = true
        
        else
          raise SyntaxError, "Unkown tag"
        end

        index = m.end(0)

        if strip_space
          pos = standalone?(template, m.begin(0), m.end(0))
          if pos
            index = pos[1]
            if last_literal
              last_literal.value = last_literal.value.rstrip($WHITESPACE)
            end
          end
        end

      end # end while

      tokens << Literal.new("str", template[index..-1])

      root.child = tokens

      return root
    end
  end


  class Context

    # look up the context stack
    #
    # @param  [String]    var_name : the key of Hash
    # @param  [Array]     contexts : contain the Hash data
    # @param  [Integer]   start    : the start index e.g. ../ will be -1
    # @return [uncertain]          : Maybe return an Array or String or other ...
    def self.lookup(var_name, contexts=[], start=0)
      if start >= 0
        start = contexts.length
      end

      for context in contexts[0..start-1].reverse
        if (context.instance_of? Hash) && (context.has_key? var_name)
          return context[var_name]
        end
      end
      return nil
    end
  end


  ##################################################
  #############    Token Base Class    #############
  ##################################################
  class Token

    attr_accessor :name, :value, :text, :child, \
                  :escape, :delimiter, :indent, :root
    
    def initialize(name, value=nil, root=nil, child=nil)
      @name = name
      @value = value
      @child = child
      @escape = false
      @delimiter = nil
      @indent = 0
      @root = root
    end

    # escape the text if @escape is true
    #
    # @param  [String] text :
    # @return [String]      : 
    def escape(text)
      if @escape
        CGI.escapeHTML text
      else
        text
      end
    end

    # find the value according to the name
    #
    # @param  [String] name     :       e.g. "../name1.name2 | upcase"
    # @param  [Array]  contexts :    
    # @return
    def lookup(name, contexts)
      arr = name.split("|").map(&:strip)
      name = arr[0]
      filters = arr[1..-1]

      # format
      if not name.start_with?(".")
        name = "./" + name
      end

      paths = name.split("/")
      last_path = paths[-1]

      refer_context = last_path == "" or last_path == "." or last_path == ".."
      paths = refer_context ? paths : paths[0..-2]

      # calculate the path level
      level = 0
      for path in paths
        if path == ".."
          level = level - 1
        elsif path != "."
          level = level + path.strip(".").split(".").length
        end
      end

      names = last_path.split(".")

      if refer_context || names[0] == ''
        begin
          value = contexts[level-1]
        rescue
          value = nil
        end
      else
        value = Context::lookup(names[0], contexts, level)
      end

      if not refer_context
        for name in names[1..-1]
          if value.instance_of? Array
            # index should be Integer type
            value = value[name.to_i]
          elsif value.instance_of? Hash
            value = value[name]
          else
            value = nil
          end
        end
      end

      pass_filter(value,filters)
    end

    # pass value the value to filter
    #
    # @param  [String] value   : value
    # @param  [Array]  filters : the key of $filters
    # @return [String]         : value after filter
    def pass_filter(value, filters)
      for f in filters
        if $filters.has_key? f
          func = $filters[f]
          begin
            value = func.call value
          rescue => err
            puts err
            exit()
          end
        end
      end
      return value   
    end

    # call child token `render` method and join the result
    #
    # @param  [Array]  contexts :
    # @param  [Hash]   partials :
    # @return [String]
    def render_child(contexts, partials)
      @child.map{ |child|
        child.render(contexts, partials)
      }.join
    end

    # abstract method
    def render
      raise NotImplementedError, 'render method should be implement in subclass'
    end

  end

  ##################################################
  #############    Token type Class    #############
  ##################################################
  class Root < Token

    def initialize(*args)
      super(*args)
      @type = "R"
    end

    def render(contexts, partials)
      return render_child(contexts, partials)
    end

  end

  class Literal < Token

    def initialize(*arg)
      super(*arg)
      @type = "L"
    end

    def render(contexts, partials)
      return escape(@value)
    end

  end

  class Variable < Token

    def initialize(*args)
      super(*args)
      @type = "V"
    end

    def render(contexts, partials)
      value = lookup(@value, contexts)
      return escape(value)
    end

  end

  class Section < Token

    def initialize(*args)
      super(*args)
      @type = "S"
    end

    def render(contexts, partials)
      var = lookup(@value, contexts)
      if not var
        return $EMPTYSTRING
      end
      
      rtn = []
      if var.instance_of? Array
        for item in var
          contexts << item
          rtn << render_child(contexts, partials)
          contexts.pop
        end
      else
        contexts << var
        rtn << render_child(contexts, partials)
        contexts.pop
      end
      # [].join => ""
      # ['item'].join => "item"
      return escape(rtn.join)
    end

  end

  class Inverted < Token

    def initialize(*arg)
      super(*arg)
      @type = "I"
    end

    def render(contexts, partials)
      var = lookup(@value, contexts)
      if var === false or var === [] or var === {}
        return render_child(contexts, partials)
      end
      return $EMPTYSTRING
    end

  end

  class Comment < Token

    def initialize(*arg)
      super(*arg)
      @type = "C"
    end

    def render(contexts, partials)
      return $EMPTYSTRING
    end

  end

  class Partial < Token

    def initialize(*arg)
      super(*arg)
      @type = "P"
    end

    def render(contexts, partials)
      partial = partials[@value]
                .sub($re_indent, "\\1" + " " * @indent)
      if not partial.end_with? "\n"
        partial = partial + "\n"
      end
      return Template::render(partial, contexts, partials)
    end

  end

end


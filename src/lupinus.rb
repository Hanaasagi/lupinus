# -*-coding:UTF-8-*-
require "cgi"


module StringExtensions
  refine String do
    # an extension that can strip other chars
    def strip(chars=nil)
      if chars
        chars = Regexp.escape(chars)
        self.gsub(/\A[#{chars}]+|[#{chars}]+\z/, "")
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
  $WHITESPACE = " \t\r\b\f"

  $re_space = Regexp.new("[" + $WHITESPACE + "]*(\n|$)")
  $re_tag = Regexp.new(format('%s([;#/!>r{]?)\s*(.*?)\s*([}]?)%s', *$DEFAULT_DELIMITERS), Regexp::MULTILINE)

  $filters = {}
  $filters['upcase'] = lambda {|s| s.upcase}
  $filters['downcase'] = lambda {|s| s.downcase}
  $filters['capitalize'] = lambda {|s| s.capitalize}


  def self.render(template, context, partials)
    new.render(template, context, partials)
  end

  def render(template, context, partials)
    contexts = [context]

    if not partials.instance_of? Hash
      raise Exception
    end

    Render::inner_render(template, contexts, partials)
  end

  class Render

    def self.inner_render(template, contexts, partials)
      delimiters = delimiters ? delimiters : $DEFAULT_DELIMITERS
      root = compiled(template, delimiters)
      root._render(contexts, partials)
    end

    def self.standalone?(text, start, end_)
      # 
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

    def self.compiled(template, delimiters=$DEFAULT_DELIMITERS)

      tokens = []
      index = 0
      sections = []
      tokens_stack = []

      root = Root.new "root"
      root.filters = $filters.clone

      while (m = $re_tag.match(template, index))
        token = nil
        last_literal = nil
        strip_space = false

        if m.begin(0) > index
          last_literal = Literal.new("str", template[index..m.begin(0)-1], root=root)
          tokens << last_literal
        end

        prefix, name, suffix = m.captures()

        if prefix == "r"
          # {{r name }}
          # raw string
          token = Variable.new(name, name, root=root)
          token.escape = false

        elsif prefix == "" && suffix == ""
          # {{ name }}
          token = Variable.new(name, name, root=root)
          token.escape = true

        elsif prefix == ";"
          # {{; comment }}
          token = Comment.new(name, root=root)
          if sections.length <= 0
            strip_space = true
          end

        elsif prefix == ">"
          token = Partial.new(name, name, root=root)
          strip_space = true
          pos = standalone?(template, m.begin(0), m.end(0))
          if pos
            token.indent = template[pos[0], m.begin(0)].length
          end

        elsif prefix == "#" || prefix == "!"
          sec_name = name.split("|")[0].strip
          if prefix == "#"
            token = Section.new(sec_name, name, root=root)
          else
            token = Inverted.new(name, name, root=root)
          end
          token.delimiter = delimiters
          tokens << token

          token = nil
          tokens_stack << tokens
          tokens = []

          sections << [sec_name, prefix, m.end(0)]
          strip_space = true

        elsif prefix == "/"
          tag_name, sec_type, text_end = sections.pop
          if tag_name != name
            raise SyntaxError, ""
          end
          child = tokens
          tokens = tokens_stack.pop()

          tokens[-1].text = template[text_end, m.begin(0)]
          tokens[-1].child = child
          strip_space = true
        
        else
          raise SyntaxError, "Unkown tag"
        
        end

        if token
          tokens << token
        end

        index = m.end(0)

        if strip_space
          pos = standalone?(template, m.begin(0), m.end(0))
          if pos
            index = pos[1]
            if last_literal
              last_literal.value = last_literal.value.strip($WHITESPACE)
            end
          end
        end
      end

      tokens << Literal.new("str", template[index..-1])

      root.child = tokens
      return root
    end
  end

  def self.lookup(var_name, contexts=[], start=0)
    # look up the context stack
    if start >= 0
      start = contexts.length
    end

    for context in contexts[0..start].reverse
      if (context.instance_of? Hash) && (context.has_key? var_name)
        return context[var_name]
      end
    end
    return nil
  end

  ##################################################
  #############    Token Base Class    #############
  ##################################################
  class Token

    attr_accessor :filters, :name, :value, :text, :child, \
                  :escape, :delimiter, :indent, :root
    
    def initialize(name, value=nil, root=nil, child=nil, text="")
      @name = name
      @value = value
      @text = text
      @child = child
      @escape = false
      @delimiter = nil
      @indent = 0
      @root = root
      @filters = {}
    end

    def escape(text)
      # escape
      if @escape
        CGI.escapeHTML text
      else
        text
      end
    end

    def _look_up(dot_name, contexts)
      list = dot_name.split("|").map(&:strip)
      dot_name = list[0]
      filters = list[1..-1]

      if not dot_name.start_with?(".")
        dot_name = "./" + dot_name
      end

      paths = dot_name.split("/")
      last_path = paths[-1]

      refer_context = last_path == "" or last_path == "." or last_path == ".."
      paths = refer_context ? paths : paths[0..-2]

      level = 0
      for path in paths
        if path == ".."
          level = level - 1
        elsif path != "."
          level = level + path.strip(".").split(".").length
        end
      end

      names = last_path.split(".")

      if refer_context || names[0] == ""
        begin
          value = contexts[level-1]
        rescue
          value = nil
        end
      else
        value = Lupinus::lookup(names[0], contexts, level)
      end

      if not refer_context
        for name in names[1..-1]
          begin
            index = name.to_i
            name = value.instance_of? Array ? name.to_i : name
            value = value[name]
          rescue
            value = nil
            break
          end
        end
      end

      for f in filters
        if @root.filters.has_key? f
          func = @root.filters[f]
          begin
            value = func.call value
          rescue
            raise Exception
          end
        end
      end

      return value
    end

    def exec_filter(value, filters)

    end

    def render_child(contexts, partials)
      rtn = []
      for child in @child

        rtn << child._render(contexts, partials)
      end
      return rtn.join
    end

    def render(contexts, partials={})
      contexts = [contexts]
      return _render(contexts, partials)
    end
  end

  class Root < Token

    def initialize(*args)
      super(*args)
      @type_string = "R"
    end

    def _render(contexts, partials)
      return render_child(contexts, partials)
    end
  end

  class Literal < Token

    def initialize(*arg)
      super(*arg)
      @type_string = "L"
    end

    def _render(contexts, partials)
      return escape(@value)
    end
  end

  class Variable < Token

    def initialize(*args)
      super(*args)
      @type_string = "V"
    end

    def _render(contexts, partials)
      value = _look_up(@value, contexts)

      if (defined? value) == "method"
        value = inner_render(value(), contexts, partials)
      end
      return escape(value)
    end
  end

  class Section < Token

    def initialize(*args)
      super(*args)
      @type_string = "S"
    end

    def _render(contexts, partials)
      val = _look_up(@value, contexts)
      if not val
        return $EMPTYSTRING
      end

      if val.instance_of? Array
        rtn = []
        for item in val
          contexts << item
          rtn << render_child(contexts, partials)
          contexts.pop
        end
        if rtn.length <= 0
          return $EMPTYSTRING
        end
        return escape(rtn.join(""))
      elsif (defined? val) == "method"
        new_template = val(@text)
        value = inner_render(new_template, contexts, partials)
      else
        contexts << val
        value = render_child(contexts, partials)
        contexts.pop
      end
      return escape(value)
    end
  end

  class Inverted < Token

    def initialize(*arg)
      super(*arg)
      @type_string = "I"
    end

    def _render(contexts, partials)
      val = _look_up(@value, contexts)
      if val
        return $EMPTYSTRING
      end
      return render_child(contexts, partials)
    end
  end

  class Comment < Token

    def initialize(*arg)
      super(*arg)
      @type_string = "C"
    end

    def _render(contexts, partials)
      return $EMPTYSTRING
    end
  end

  class Partial < Token

    def initialize(*arg)
      super(*arg)
      @type_string = "P"
    end

    def _render(contexts, partials)
      partial = partials[@value]

      # !!!
      return Render::inner_render(partial, contexts, partials)
    end
  end
end






# test
require "json"
template_text = <<~EOF
<h1>Today{{; ignore me }}.</h1>
<h1>{{ header }}</h1>
{{# bug }}
{{/ bug }}

{{# items }}
  {{# first }}
    <li><strong>{{name | upcase}}</strong></li>
  {{/ first }}
  {{# link }}
    <li><a href="{{url}}">{{name}}</a></li>
  {{/ link }}
{{/ items }}

{{! empty }}
  <p>The list is empty.</p>
{{/ empty }}
{{> hello }}
EOF

context_text = <<~EOF
{
  "header": "Colors",
  "items": [
      {"name": "red", "first": true, "url": "#Red"},
      {"name": "green", "link": true, "url": "#Green"},
      {"name": "blue", "link": true, "url": "#Blue"}
  ],
  "empty": false,
  "hello": "{{ name }}",
  "name" : "miziha"
}
EOF

context = JSON.parse(context_text)
puts Lupinus.render(template_text, context,{'hello'=>'{{name}}'}) 



# template_text = <<~EOF
# {{#repo}}
#   <b></b>
# {{/repo}}
# {{!repo}}
#   No repos :(
# {{/repo}}
# EOF

# context_text = <<~EOF
# {
#   "repo": []
# }
# EOF
# context = JSON.parse(context_text)
# puts Lupinus.render(template_text, context) 

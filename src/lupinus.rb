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
  $re_tag = Regexp.new(format('%s([#^>&{/!]?)\s*(.*?)\s*([}]?)%s', *$DEFAULT_DELIMITERS), Regexp::MULTILINE)
  $filters = {}

  def self.render(*arg, **kwargs)
    new.render(*arg, **kwargs)
  end

  def render(template, context, partials={}, delimiters=nil)
    contexts = [context]

    if not partials.instance_of? Hash
      raise Exception
    end

    inner_render(template, contexts, partials, delimiters)
  end

  def inner_render(template, contexts, partials={}, delimiters=nil)
    delimiters = delimiters ? delimiters : $DEFAULT_DELIMITERS
    parent_token = compiled(template, delimiters)
    parent_token._render(contexts, partials)
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

  def standalone?(text, start, end_)
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

  def compiled(template, delimiters=$DEFAULT_DELIMITERS)

    tokens = []
    index = 0
    sections = []
    tokens_stack = []

    root = Root.new "root"
    root.filters = $filters.clone

    m = $re_tag.match(template, index)
    while m
      token = nil
      last_literal = nil
      strip_space = false

      if m.begin(0) > index
        last_literal = Literal.new("str", template[index..m.begin(0)-1], root=root)

        tokens << last_literal
      end

      prefix, name, suffix = m.captures()


      if prefix == "{" && suffix == "}"
        token = Variable.new(name, name, root=root)
      elsif prefix == "" && suffix == ""
        token = Variable.new(name, name, root=root)
        token.escape = true
      elsif suffix != "" && suffix != nil
        raise SyntaxError, "Invalid token"
      elsif prefix == "&"
        token = Variable.new(name, name, root=root)
      elsif prefix == "!"
        token = Comment.new(name, root=root)
        if len(sections) <= 0
          strip_space = true
        end
      elsif prefix == ">"
        token = Paritial.new(name, name, root=root)
        strip_space = true
        pos = standalone?(template, m.begin(0), m.end(0))
        if pos
          token.indent = template[pos[0], m.begin(0)].length
        end
      elsif prefix == "#" || prefix == "^"
        sec_name = name.split("|")[0].strip
        if prefix == "#"
          token = Section.new(sec_name, name, root=root)
        else
          Inverted.new(name, name, root=root)
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
          raise SyntaxError, "fuck ruby"
        end
        children = tokens
        tokens = tokens_stack.pop()

        tokens[-1].text = template[text_end, m.begin(0)]
        tokens[-1].children = children
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
      m = $re_tag.match(template, index)
    end
    tokens << Literal.new("str", template[index..-1])

    root.children = tokens
    return root
  end



  class Token

    attr_accessor :filters, :name, :value, :text, :children, :escape, :delimiter, :indent, :root
    def initialize(name, value=nil, text="", children=nil, root=nil)
      @name = name
      @value = value
      @text = text
      @children = children
      @excape = false
      @delimiter = nil
      @indent = 0
      @root = root
      @filters = {}
    end

    def _escape(text)
      rtn = text ? text : $EMPTYSTRING

      if @excape
        CGI.escapeHTML rtn
      else
        rtn
      end
    end

    def _look_up(dot_name, contexts)
      list = dot_name.split("|").map(&:strip)
      dot_name =list[0]
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
        begin
          func = @root.filters[f]
          value = func(value)
        rescue
          next
        end
      end

      return value
    end

    def _render_children(contexts, partials)
      rtn = []
      for child in @children

        rtn << child._render(contexts, partials)
      end
      return rtn.join("")
    end

    def _get_str(indent)
      rtn = []
      rtn << " " * indent + "[("
      rtn << @type_string
      rtn << ","
      rtn << @name
      if @value
        rtn << ","
        rtn << @value
      end
      rtn << ")"
      if @children
        for c in @children
          rtn << "\n"
          rtn << c._get_str(indent+4)
        end
      end
      rtn << "]"
      return rtn.join("")
    end

    def to_s
      return _get_str(0)
    end

    def render(contexts, partials={})
      contexts = [contexts]
      return _render(contexts, partials)
    end
  end

  class Root < Token

    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      @type_string = "R"
    end

    def _render(contexts, partials)
      return _render_children(contexts, partials)
    end
  end

  class Literal < Token
    def initialize(*arg)
      super(*arg)
      @type_string = "L"
    end
    def _render(contexts, partials)
      return _escape(@value)
    end
  end

  class Variable < Token

    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      @type_string = "V"
    end

    def _render(contexts, partials)
      value = _look_up(@value, contexts)

      if (defined? value) == "method"
        value = inner_render(value(), contexts, partials)
      end
      return _escape(value)
    end
  end

  class Section < Token

    def initialize(*args, **kwargs)
      super(*args, **kwargs)
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
          rtn << _render_children(contexts, partials)
          contexts.pop
        end
        if rtn.length <= 0
          return $EMPTYSTRING
        end
        return _escape(rtn.join(""))
      elsif (defined? val) == "method"
        new_template = val(@text)
        value = inwner_render(new_template, contexts, partials, @delimiter)
      else
        contexts << val
        value = _render_children(contexts, partials)
        contexts.pop
      end
      return _escape(value)
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
      return _render_children(contexts, partials)
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
      return inner_render(partial, contexts, partials, @delimiter)
    end
  end
end






# test
require "json"
template_text = <<~EOF
<h1>{{header}}</h1>
{{#bug}}
{{/bug}}

{{#items}}
  {{#first}}
    <li><strong>{{name}}</strong></li>
  {{/first}}
  {{#link}}
    <li><a href="{{url}}">{{name}}</a></li>
  {{/link}}
{{/items}}

{{#empty}}
  <p>The list is empty.</p>
{{/empty}}
EOF

context_text = <<~EOF
{
  "header": "Colors",
  "items": [
      {"name": "red", "first": true, "url": "#Red"},
      {"name": "green", "link": true, "url": "#Green"},
      {"name": "blue", "link": true, "url": "#Blue"}
  ],
  "empty": false
}
EOF

context = JSON.parse(context_text)
puts Lupinus.render(template_text, context) 



template_text = <<~EOF
{{#repo}}
  <b>{{name}}</b>
{{/repo}}
EOF

context_text = <<~EOF
 {
  "repo": [
    { "name": "resque" },
    { "name": "hub" },
    { "name": "rip" }
  ]
}
EOF
context = JSON.parse(context_text)
puts Lupinus.render(template_text, context) 

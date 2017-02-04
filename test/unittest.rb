require 'minitest/autorun'
require '../src/lupinus'


class LupinusTest < MiniTest::Unit::TestCase


  def test_normal_text
    template = "Hello\tWorld\n"
    assert_equal template, Lupinus.render(template, {})
  end

  def test_variable
    template = "{{ var }}"
    context = {"var"=>"Hello World"}
    assert_equal "Hello World", Lupinus.render(template, context)
  end

  def test_comment
    template = "{{; hhhh }}"
    assert_equal "", Lupinus.render(template, {})
  end

  def test_section
    template =<<~EOF
    {{# member }}:
      {{ name }}
    {{/ member }}
    EOF

    context = {
      "member"=>[
        {"name"=>"Ruby Rose"},
        {"name"=>"Weiss Schnee"},
        {"name"=>"Blake Belladonna"},
        {"name"=>"Yang Xiao Long"}
      ]
    }

    # it has two space
    correct_text =<<~EOF
    --
      Ruby Rose
      Weiss Schnee
      Blake Belladonna
      Yang Xiao Long
    EOF

    assert_equal correct_text[3..-1], Lupinus.render(template, context)
  end


  def test_inverted
    template =<<~EOF
    {{# csv_data }}
      {{ data }}, {{ name }}
    {{/ csv_data }}
    {{! csv_data }}
      It is empty
    {{/ csv_data }}
    EOF

    assert_equal "  It is empty\n", Lupinus.render(template, {"csv_data"=>[]})
  end

  def test_partial
    template ="{{> header }}"

    context = {"title"=>"Lupinus"}

    partial = {"header"=>"<title>{{title}}</title>"} 
    assert_equal "<title>Lupinus</title>\n", Lupinus.render(template, context, partial)
  end

  def test_nesting
    template = <<~EOF
    {{# country }}
      {{# state }}
        {{ name }} in {{ ../name }}
      {{/ state}}
    {{/ country }}
    EOF

    context = {
      "country"=>[{
        "name"=>"America",
        "state"=>[{
          "name"=>"California"
        }]
      }]
    }

    assert_equal "    California in America\n", Lupinus.render(template, context)
  end
end

# lupinus  
Ruby template similar to Mustache  

```
     ∩
    ⊂○⊃　∩
     ∪　⊂○⊃
   ＼│　 ∪
```

### Quick example

Now you have following template:  

	template = <<~EOF
	<h1>Welcome{{; ignore me }}.</h1>
	{{# bug }}
	<h1> I find something wrong </h1> 
	{{/ bug }}

	{{# items }}
	    <li><strong>{{ name }}</strong>&nbsp;{{ price }} USD</li>
	{{/ items }}

	{{! items }}
	<strong>no dishes today</strong>
	{{/ items }}
	EOF

And following data  

	context = {
	  "items"=> [
	      {"name"=> "spaghetti", "price"=> "0"},
	      {"name"=> "bacon", "price"=> "0"},
	      {"name"=> "salad", "price"=> "0"}
	  ],
	}

call `Lupinus.render(template, context)` to render the template  
will return following text  

	<h1>Welcome.</h1>                             

	    <li><strong>spaghetti</strong>&nbsp;0 USD</li>
	    <li><strong>bacon</strong>&nbsp;0 USD</li>
	    <li><strong>salad</strong>&nbsp;0 USD</li>


### Usage  

There are no if statements, else clauses, or for loops. Instead there are only tags. Some tags are replaced with a value, some nothing, and others a series of values. following document explains the different tag types.

#### Variables  
`{{ name }}` tag will try to find the name key in the current context and replace.  
 All the variables are HTML escaped by default. If you want to return raw text, use `{{r name }}`
 
Template  
 
    {{ name }}
    {{ age }}
    {{r introduction }}    

Hash  

    {
    "name"=>"charlotte",
    "age"=>"19",
    "introduction"=>"my homepage is <a>...</a>"
    }

Output  

	charlotte
	19
	my homepage is <a>...</a> 

#### Sections  
`{{# name }}` `{{/ name }}` is considered as sections.
Sections render blocks of text one or more times, depending on the value of the key in the current context. If the key exists and has a value of false or an empty list, the HTML in sections will not be displayed. Besides, an inverted section begins with `{{! name }}`.  If the key doesn't exist, is false, or is empty, the sections' inner HTML will be displayed.

Template  

    {{# person }}
    {{ name }}
    {{/ person }}    

Hash  

    {
      "person"=>[
        {"name"=>"ruby"},
        {"name"=>"weiss"},
        {"name"=>"blake"},
        {"name"=>"yang"}
      ]
    }
    
Output  

    ruby
    weiss
    blake
    yang

#### Comments
`{{! this is comment tag}}`


#### Partials  

`{{> name }}` will load extern template and render

Template

    {{> header }}
    
Hash

    {
      "title"=>"Index Page"
    }
    
 Partial
 
    {
      "header"=>"<title>{{ title }}</title>"
    }

Output

    <title>Index Page</title>

### License  
MIT License  

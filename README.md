# lupinus  
Ruby template similar to Mustache  

     ∩
    ⊂○⊃　∩
     ∪　⊂○⊃
    ＼│　　∪


###Quick example

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



###License  
MIT License  

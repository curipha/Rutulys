Rutulys
=======
Rutulys transforms plain text into static websites.
It is designed as a content management system with least functionality.

For example, this program does NOT contain plain text parser (e.g. Markdown parser).

It just outputs a HTML file from a text file with some processing.
You can define 'some processing' as you want.
(Of course, you can define it as converting from Markdown to HTML.)


How to use
----------

```
% cd path/to/sourcedir
% ./rutulys.rb
```


### Directory structure

```
@outputpath
  \_ index.html
  \_ style.css
  \_ (Cache file)
  \_ ...

@sourcepath
  \_ config.yaml
  \_ template.html
  \_ (Source file)
  \_ ...

@backuppath
    \_ (URL encoded cache title
        \_ (URL encoded cache title with suffix to specify date and time)
        \_ ...
    \_ ...
```

`@outputpath` indicates the same location as `@baseuri`.



### Pre-defined files

You can use symbolic link when pre-defined file is located at another location.

#### config.yaml
Rutulys configuration file.

#### template.html
Used for a HTML template.

There are some placeholder to be replaced.

- `%{title}`
- `%{author}`
- `%{generator}`
- `%{stylesheet}`
- `%{baseuri}`
- `%{canonical}`
- `%{modified}`
- `%{next}`
- `%{prev}`
- `%{content}`

#### style.css
Used for style sheet.

#### index.html
This file is not a pre-defined file but is noticeable.

Rutulys generates `index.html` automatically as symbolic link to the newest cache file.
If `index.html` is already exists, it will be replaced.


Related rich products
---------------------
- blosxom http://blosxom.sourceforge.net/
- Jekyll  http://jekyllrb.com/


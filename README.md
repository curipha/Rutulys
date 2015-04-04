Rutulys
=======
Rutulys transforms plain text into static websites.
It is designed as a content management system with minimum functionality.

It just outputs a HTML file from a markdown text using [Redcarpet](https://github.com/vmg/redcarpet) with [Rouge](https://github.com/jneen/rouge).

Rutulys requires Ruby 2.1.0 and over with following gems.

- `redcarpet`
- `rouge`
- `safe_yaml`

How to use
----------
```
% cd path/to/sourcedir
% rutulys.rb [command]
```

### Command

#### `--build`
Build the whole website.

### Wording

#### Deploy path (Deploying point)
As known as `@deploypath`.

Processed files will be outputted to this directory.
A parent directory of this path MUST be writable by Rutulys.

`index.html` will be created in this directory automatically.

This directory will be cleaned on build.

#### Source path
As known as `@sourcepath`.

Original text file should be in `library` directory of this directory.
The file name is used in processed file.
It means a file name will be a part of URI.

All of file in `library` directory will be the target of processing.
Subdirectory of this directory and its children are excluded.

Other files (e.g. style sheets, images and so on) should be in `asset` directory of this directory.
All files in this directory will be copied to the root of deploy point as it is.

`config.yaml` and `template.html` must be in this directory.
They are the system file.

Your current directory becomes source path.
Before running Rutulys, you have to `cd` to your source path.

### Directory structure

```
@deploypath
  \_ index.html
  \_ .htaccess
  \_ style.css
  \_ ...
  \_ image
      \_ ...
  \_ archive
       \_ (Cache file)
       \_ ...
  \_ category
       \_ (Cache file)
       \_ ...

@sourcepath
  \_ config.yaml
  \_ template.html
  \_ asset
       \_ .htaccess
       \_ styles.css
       \_ ...
       \_ image
            \_ ...
  \_ library
       \_ (Source file)
       \_ ...
```

### Pre-defined files

You can use symbolic link when pre-defined file is located at another location.

Check `config.yaml` and `template.html` files in `sample` directory.

#### config.yaml
Rutulys configuration file.

#### template.html
Used for a HTML template.

There are some placeholder to be replaced.

##### `%{title}`
It will be replaced by the file name of source file without specified extension string.

```HTML
<title>%{title} | Your Site Name</title>
```

##### `%{canonical}`
It will be replaced by the canonical URI to this document.
This string is prepared for search engine bot.

```HTML
<link rel="canonical" href="%{canonical}" />
```

##### `%{next}`, `%{prev}`
It will be replaced by the navigation link.
If it is the newest or oldest file, the text will be blank.

```HTML
<nav>
  %{next}
  %{prev}
</nav>
```

##### `%{content}`, `%{modified}`, `%{category}`
`%{content}` will be replaced by a main content text.
`%{modified}` will be replaced by the modified time string of a source file.
`%{category}` will be replaced by the link list of categories of a source file.

```HTML
<article>
  <div class="date">%{modified}</div>
  <div class="tags">%{category}</div>
  <div class="main">%{content}</div>
</article>
```

##### `%{categlist}`
It will be replaced by the category list of this site.

```HTML
<footer>
  %{categlist}
</footer>
```

#### index.html
This file is not a pre-defined file but is noticeable.

Rutulys generates `index.html` automatically as symbolic link to the newest cache file.
If `index.html` is already exists, it will be replaced.


Related rich products
---------------------
- blosxom http://blosxom.sourceforge.net/
- Jekyll  http://jekyllrb.com/


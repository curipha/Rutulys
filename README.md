Rutulys
=======
Rutulys transforms plain text into static websites.
It is designed as a content management system with least functionality.

For example, this program does NOT contain plain text parser (e.g. Markdown parser).

It just outputs a file from a text file with some processing.
You can define 'some processing' as you want.
(Of course, you can define it as converting from Markdown to HTML.)


How to use
----------
```
% cd path/to/sourcedir
% rutulys.rb [command]
```

### Command

#### `add`
Process newly added source file(s) only.

#### `rebuild`
All files in source directory will be processed.

In case of follows, use this mode.

- Update `template.html`
- Remove/Change/Rename existing source file

Otherwise, it will be inconsistent.

### Wording

#### Output path
As known as `@outputpath`.

Processed files (maybe HTML files) will be outputted to this directory.
This directory MUST be writable by Rutulys.

`index.html` will be created in this directory automatically.
`style.css` should be created here.

Processed file name is converted from original one to URL-encoded string.
As a character encoding, we use UTF-8.
(e.g. `あいうえお` will be `%E3%81%82%E3%81%84%E3%81%86%E3%81%88%E3%81%8A`.)

#### Source path
As known as `@sourcepath`.

Original text file should be in this directory.
The file name is used in processed file.
It means a file name will be a part of URI.

All of file in this directory will be the target of processing.
Subdirectory of this directory and its children are excluded.
If you want to ignore file(s) in this directory from processing, start the filename with string sandwiched by `#`.
(e.g. `#DRAFT# ignore me` will be ignore. `#include not ignored` and `Any string #123 and #345` will not.)

`config.yaml` and `template.html` must be in this directory.
They are the system file.

Your current directory becomes source path.
Before running Rutulys, you have to `cd` to your source path.

#### Backup path
As known as `@backuppath`.

Just an archive directory.
This directory MUST be writable by Rutulys.
That's all.

Rutulys will create one directory for each source (original) text file.
Backup files will be created in the directory.

Backup feature cannot be disabled.
I'm **sure** that the day you use this backup will come.

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

- `%{title}` Title placeholder
  - `<title>%{title} | Your Site Name</title>`
- `%{generator}`
  - `<meta name="generator" content="%{generator}" />`
- `%{baseuri}`
  - `<base href="%{baseuri}" />`
- `%{stylesheet}`
  - `<link rel="stylesheet" type="text/css" href="%{stylesheet}" />`
- `%{canonical}`
  - `<link rel="canonical" href="%{canonical}" />`
- `%{next}`, `%{prev}`
  - `<div id="nav"><div id="next">%{next}</div><div id="prev">%{prev}</div></div>`
- `%{content}`, `%{modified}`
  - `<div id="main"><div class="date">%{modified}</div>%{content}</div>`

#### style.css
Used for style sheet.

#### index.html
This file is not a pre-defined file but is noticeable.

Rutulys generates `index.html` automatically as symbolic link to the newest cache file.
If `index.html` is already exists, it will be replaced.


Extend Rutulys
--------------
Just inherit `Rutulys` class and extend it.

`parser` method should be overridden to implement text syntax parser.


Related rich products
---------------------
- blosxom http://blosxom.sourceforge.net/
- Jekyll  http://jekyllrb.com/


--[[
diagram-generator – create images and figures from code blocks.

This Lua filter is used to create images with or without captions
from code blocks. Currently PlantUML, GraphViz, Tikz, and Python
can be processed. For further details, see README.md.

Copyright: © 2018-2021 John MacFarlane <jgm@berkeley.edu>,
             2018 Florian Schätzig <florian@schaetzig.de>,
             2019 Thorsten Sommer <contact@sommer-engineering.com>,
             2019-2023 Albert Krewinkel <albert+pandoc@zeitkraut.de>
License:   MIT – see LICENSE file for details
]]
-- Module pandoc.system is required and was added in version 2.7.3
PANDOC_VERSION:must_be_at_least '3.0'

local system = require 'pandoc.system'
local utils = require 'pandoc.utils'
local stringify = function (s)
  return type(s) == 'string' and s or utils.stringify(s)
end
local with_temporary_directory = system.with_temporary_directory
local with_working_directory = system.with_working_directory

-- The PlantUML path. If set, uses the environment variable PLANTUML or the
-- value "plantuml.jar" (local PlantUML version). In order to define a
-- PlantUML version per pandoc document, use the meta data to define the key
-- "plantuml_path".
local plantuml_path = os.getenv("PLANTUML") or "plantuml.jar"

-- The Inkscape path. In order to define an Inkscape version per pandoc
-- document, use the meta data to define the key "inkscape_path".
local inkscape_path = os.getenv("INKSCAPE") or "inkscape"

-- The Python path. In order to define a Python version per pandoc document,
-- use the meta data to define the key "python_path".
local python_path = os.getenv("PYTHON") or "python"

-- The Python environment's activate script. Can be set on a per document
-- basis by using the meta data key "activatePythonPath".
local python_activate_path = os.getenv("PYTHON_ACTIVATE")

-- The Java path. In order to define a Java version per pandoc document,
-- use the meta data to define the key "java_path".
local java_path = os.getenv("JAVA_HOME")
if java_path then
    java_path = java_path .. package.config:sub(1,1) .. "bin"
        .. package.config:sub(1,1) .. "java"
else
    java_path = "java"
end

-- The dot (Graphviz) path. In order to define a dot version per pandoc
-- document, use the meta data to define the key "dot_path".
local dot_path = os.getenv("DOT") or "dot"

-- The pdflatex path. In order to define a pdflatex version per pandoc
-- document, use the meta data to define the key "pdflatex_path".
local pdflatex_path = os.getenv("PDFLATEX") or "pdflatex"

-- The asymptote path. There is also the metadata variable
-- "asymptote_path".
local asymptote_path = os.getenv ("ASYMPTOTE") or "asy"

-- The default format is SVG i.e. vector graphics:
local filetype = "svg"
local mimetype = "image/svg+xml"

-- Check for output formats that potentially cannot use SVG
-- vector graphics. In these cases, we use a different format
-- such as PNG:
if FORMAT == "docx" then
  filetype = "png"
  mimetype = "image/png"
elseif FORMAT == "pptx" then
  filetype = "png"
  mimetype = "image/png"
elseif FORMAT == "rtf" then
  filetype = "png"
  mimetype = "image/png"
end

-- Execute the meta data table to determine the paths. This function
-- must be called first to get the desired path. If one of these
-- meta options was set, it gets used instead of the corresponding
-- environment variable:
local function configure (meta)
  plantuml_path = stringify(
    meta.plantuml_path or meta.plantumlPath or plantuml_path
  )
  inkscape_path = stringify(
    meta.inkscape_path or meta.inkscapePath or inkscape_path
  )
  python_path = stringify(
    meta.python_path or meta.pythonPath or python_path
  )
  python_activate_path =
    meta.activate_python_path or meta.activatePythonPath or python_activate_path
  python_activate_path = python_activate_path and stringify(python_activate_path)
  java_path = stringify(
    meta.java_path or meta.javaPath or java_path
  )
  dot_path = stringify(
    meta.path_dot or meta.dotPath or dot_path
  )
  pdflatex_path = stringify(
    meta.pdflatex_path or meta.pdflatexPath or pdflatex_path
  )
  asymptote_path = stringify(
     meta.asymptote_path or meta.asymptotePath or asymptote_path
  )
end

-- Call plantuml.jar with some parameters (cf. PlantUML help):
local function plantuml(puml, filetype)
  return pandoc.pipe(
    java_path,
    {"-jar", plantuml_path, "-t" .. filetype, "-pipe", "-charset", "UTF8"},
    puml
  )
end

-- Call dot (GraphViz) in order to generate the image
-- (thanks @muxueqz for this code):
local function graphviz(code, filetype)
  return pandoc.pipe(dot_path, {"-T" .. filetype}, code)
end

--
-- TikZ
--

--- LaTeX template used to compile TikZ images. Takes additional
--- packages as the first, and the actual TikZ code as the second
--- argument.
local tikz_template = [[
\documentclass{standalone}
\usepackage{tikz}
%% begin: additional packages
%s
%% end: additional packages
\begin{document}
%s
\end{document}
]]

--- Writes the contents into a file at the given path.
local function write_file (filepath, content)
  local fh = io.open(filepath, 'wb')
  fh:write(content)
  fh:close()
end

--- Converts an image file from to a different format. The formats must
--- be given as MIME types.
local function convert_image_file (filename, from_mime, to_mime, opts)
  local args
  if to_mime == 'image/png' then
    args = pandoc.List{'--export-type=png', '--export-dpi=300'}
  elseif to_mime == 'image/svg+xml' then
    args = pandoc.List{'--export-type=svg', '--export-plain-svg'}
  else
    return nil
  end
  args:insert('--export-filename=-')
  args:insert(filename)
  return pandoc.pipe('inkscape', args, '')
end

--- Compile LaTeX with Tikz code to an image
local function tikz2image(src, filetype, additional_packages)
  return with_temporary_directory("tikz2image", function (tmpdir)
    return with_working_directory(tmpdir, function ()
      -- Define file names:
      local file_template = "%s/tikz-image.%s"
      local tikz_file = file_template:format(tmpdir, "tex")
      local pdf_file = file_template:format(tmpdir, "pdf")
      local tex_code = tikz_template:format(additional_packages or '', src)
      write_file(tikz_file, tex_code)

      -- Execute the LaTeX compiler:
      pandoc.pipe(pdflatex_path, {'-output-directory', tmpdir, tikz_file}, '')

      return convert_image_file(pdf_file, 'application/pdf', 'image/svg+xml')
    end)
  end)
end

-- Run Python to generate an image:
local function py2image(code, filetype)

  -- Define the temp files:
  local outfile = string.format('%s.%s', os.tmpname(), filetype)
  local pyfile = os.tmpname()

  -- Replace the desired destination's file type in the Python code:
  local extendedCode = string.gsub(code, "%$FORMAT%$", filetype)

  -- Replace the desired destination's path in the Python code:
  extendedCode = string.gsub(extendedCode, "%$DESTINATION%$", outfile)

  -- Write the Python code:
  local f = io.open(pyfile, 'w')
  f:write(extendedCode)
  f:close()

  -- Execute Python in the desired environment:
  local pycmd = python_path .. ' ' .. pyfile
  local command = python_activate_path
    and python_activate_path .. ' && ' .. pycmd
    or pycmd
  os.execute(command)

  -- Try to open the written image:
  local r = io.open(outfile, 'rb')
  local imgData = nil

  -- When the image exist, read it:
  if r then
    imgData = r:read("*all")
    r:close()
  else
    io.stderr:write(string.format("File '%s' could not be opened", outfile))
    error 'Could not create image from python code.'
  end

  -- Delete the tmp files:
  os.remove(pyfile)
  os.remove(outfile)

  return imgData
end

--
-- Asymptote
--

local function asymptote(code, filetype)
  local mimetype = filetype == 'png'
    and 'image/png'
    or 'image/svg+xml'
  return with_temporary_directory(
    "asymptote",
    function(tmpdir)
      return with_working_directory(
        tmpdir,
        function ()
          local pdf_file = "pandoc_diagram.pdf"
          pandoc.pipe(
            asymptote_path,
            {'-tex', 'pdflatex', "-o", "pandoc_diagram", '-'},
            code
          )
          return convert_image_file(pdf_file, 'application/pdf', mimetype)
      end)
  end)
end

-- Executes each document's code block to find matching code blocks:
local function code_to_figure (block)
  -- Using a table with all known generators i.e. converters:
  local converters = {
    plantuml = plantuml,
    graphviz = graphviz,
    tikz = tikz2image,
    py2image = py2image,
    asymptote = asymptote,
  }

  -- Check if a converter exists for this block. If not, return the block
  -- unchanged.
  local img_converter = converters[block.classes[1]]
  if not img_converter then
    return nil
  end

  -- Call the correct converter which belongs to the used class:
  local success, img = pcall(img_converter, block.text,
      filetype, block.attributes["additionalPackages"] or nil)

  -- Bail if an error occured; img contains the error message when that
  -- happens.
  if not (success and img) then
    io.stderr:write(tostring(img or "no image data has been returned."))
    io.stderr:write('\n')
    error 'Image conversion failed. Aborting.'
  end

  -- If we got here, then the transformation went ok and `img` contains
  -- the image data.

  -- Use the block's filename attribute or create a new name by hashing the
  -- image content.
  local basename, extension = pandoc.path.split_extension(
    block.attributes.filename or pandoc.sha1(img)
  )
  local fname = basename .. (extension ~= '' and extension or '.' .. filetype)

  -- Store the data in the media bag:
  pandoc.mediabag.insert(fname, mimetype, img)

  local enable_caption = nil

  -- If the user defines a caption, read it as Markdown.
  local caption = block.attributes.caption
    and pandoc.read(block.attributes.caption).blocks
    or pandoc.Blocks{}
  local alt = pandoc.utils.blocks_to_inlines(caption)
  local fig_attr = {
    id = block.identifier,
    name = block.attributes.name,
  }
  local img_attr = {
    width = block.attributes.width,
    height = block.attributes.height,
  }
  local img_obj = pandoc.Image(alt, fname, "", img_attr)

  -- Create a figure that contains just this image.
  return pandoc.Figure(pandoc.Plain{img_obj}, caption, fig_attr)
end

function Pandoc (doc)
  configure(doc.meta)
  return doc:walk {
    CodeBlock = code_to_figure,
  }
end

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

local path_can_be_nil = {
  python_activate = true,
}
--- Table containing program paths. If the program has no explicit path set,
--- then the value of the environment variable with the uppercase name of the
--- program is used when defined. The fallback is to use just the program name,
--- which will cause the program to be looked up in the PATH.
local path = setmetatable(
  {},
  {
    __index = function (tbl, key)
      local execpath = key == 'asv' and
        (os.getenv 'ASYMPTOTE' or os.getenv 'ASY') or
        os.getenv(key:upper())

      if not execpath or execpath == '' then
        execpath = not path_can_be_nil[key]
          and key
          or nil
      end

      tbl[key] = execpath
      return execpath
    end
  }
)

-- Execute the meta data table to determine the paths. This function
-- must be called first to get the desired path. If one of these
-- meta options was set, it gets used instead of the corresponding
-- environment variable:
local function configure (meta)
  local conf = meta.diagram or {}
  for name, execpath in pairs(conf.path or {}) do
    path[name] = stringify(execpath)
  end
end

-- Call plantuml with some parameters (cf. PlantUML help):
local function plantuml(puml)
  local args = {"-tsvg", "-pipe", "-charset", "UTF8"}
  return pandoc.pipe(path['plantuml'], args, puml), 'image/svg+xml'
end

-- Call dot (GraphViz) in order to generate the image
-- (thanks @muxueqz for this code):
local function graphviz(code)
  return pandoc.pipe(path['dot'], {"-Tsvg"}, code), 'image/svg+xml'
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

--- Reads the contents of a file.
local function read_file (filepath)
  local fh = io.open(filepath, 'rb')
  local contents = fh:read('a')
  fh:close()
  return contents
end

--- Writes the contents into a file at the given path.
local function write_file (filepath, content)
  local fh = io.open(filepath, 'wb')
  fh:write(content)
  fh:close()
end

--- Compile LaTeX with TikZ code to an image
local function tikz2image(src, additional_packages)
  return with_temporary_directory("tikz2image", function (tmpdir)
    return with_working_directory(tmpdir, function ()
      -- Define file names:
      local file_template = "%s/tikz-image.%s"
      local tikz_file = file_template:format(tmpdir, "tex")
      local pdf_file = file_template:format(tmpdir, "pdf")
      local tex_code = tikz_template:format(additional_packages or '', src)
      write_file(tikz_file, tex_code)

      -- Execute the LaTeX compiler:
      pandoc.pipe(path['pdflatex'], {'-output-directory', tmpdir, tikz_file}, '')

      return read_file(pdf_file), 'application/pdf'
    end)
  end)
end

-- Run Python to generate an image:
local function py2image(code)

  -- Define the temp files:
  local outfile = string.format('%s.%s', os.tmpname())
  local pyfile = os.tmpname()

  -- Replace the desired destination's path in the Python code:
  extendedCode = string.gsub(extendedCode, "%$DESTINATION%$", outfile)

  -- Write the Python code:
  local f = io.open(pyfile, 'w')
  f:write(extendedCode)
  f:close()

  -- Execute Python in the desired environment:
  local pycmd = path['python'] .. ' ' .. pyfile
  local command = path['python_activate']
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

  return imgData, 'image/svg+xml'
end

--
-- Asymptote
--

local function asymptote(code)
  return with_temporary_directory("asymptote", function(tmpdir)
    return with_working_directory(tmpdir, function ()
      local pdf_file = "pandoc_diagram.pdf"
      local args = {'-tex', 'pdflatex', "-o", "pandoc_diagram", '-'}
      pandoc.pipe(path['asy'], args, code)
      return read_file(pdf_file), 'application/pdf'
    end)
  end)
end

local function format_accepts_pdf_images (format)
  return format == 'latex' or format == 'context'
end

local function extension_for_mimetype (mimetype)
  return
    (mimetype == 'application/pdf' and 'pdf') or
    (mimetype == 'image/svg+xml' and 'svg') or
    (mimetype == 'image/png' and 'png')
end

--- Converts a PDF to SVG.
local pdf2svg = function (imgdata)
  local pdf_file = os.tmpname() .. '.pdf'
  write_file(pdf_file, imgdata)
  local args = {
    '--export-type=svg',
    '--export-plain-svg',
    '--export-filename=-',
    pdf_file
  }
  return pandoc.pipe(path['inkscape'], args, ''), os.remove(pdf_file)
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
  local success, img, imgtype = pcall(img_converter, block.text,
       block.attributes["additionalPackages"] or nil)

  -- Bail if an error occured; img contains the error message when that
  -- happens.
  if not (success and img) then
    io.stderr:write(tostring(img or "no image data has been returned."))
    io.stderr:write('\n')
    error 'Image conversion failed. Aborting.'
  end

  if not imgtype then
    error 'MIME-type of image is unknown.'
  end

  -- If we got here, then the transformation went ok and `img` contains
  -- the image data.
  if imgtype == 'application/pdf' and not format_accepts_pdf_images(FORMAT) then
    img, imgtype = pdf2svg(img), 'image/svg+xml'
  end

  -- Use the block's filename attribute or create a new name by hashing the
  -- image content.
  local basename, extension = pandoc.path.split_extension(
    block.attributes.filename or pandoc.sha1(img)
  )
  local fname = basename ..
    (extension ~= '' and extension or '.' .. extension_for_mimetype(imgtype))

  -- Store the data in the media bag:
  pandoc.mediabag.insert(fname, imgtype, img)

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

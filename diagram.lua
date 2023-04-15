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

--- List of paths that should not be set to any value if the respective
--- env var is undefined.
local path_can_be_nil = {
  python_activate = true,
}
--- Table containing program paths. If the program has no explicit path
--- set, then the value of the environment variable with the uppercase
--- name of the program is used when defined. The fallback is to use
--- just the program name, which will cause the program to be looked up
--- in the PATH.
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

--
-- Common code to convert code to a figure.
--

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

--- Table containing mapping from the names of supported diagram engines
--- to the converter functions.
local diagram_engines = {
  asymptote = {asymptote, '%%'},
  dot       = {graphviz, '//'},
  graphviz  = {graphviz, '//'},
  plantuml  = {plantuml, "'"},
  py2image  = {py2image, '#'},
  tikz      = {tikz2image, '%%'},
}

local function properties_from_code (code, comment_start)
  local props = {}
  local pattern = comment_start:gsub('%p', '%%%1') .. '| ' ..
    '([-_%w]+): ([^\n]*)\n'
  for key, value in code:gmatch(pattern) do
    if key == 'fig-cap' then
      props['caption'] = value
    else
      props[key] = value
    end
  end
  return props
end

local function diagram_properties (cb, option_start)
  local attribs = option_start
    and properties_from_code(cb.text, option_start)
    or {}
  for key, value in pairs(cb.attributes) do
    attribs[key] = value
  end

  -- Read caption attribute as Markdown
  local caption = attribs.caption
    and pandoc.read(attribs.caption).blocks
    or pandoc.Blocks{}
  local fig_attr = {
    id = cb.identifier ~= '' and cb.identifier or attribs.label,
    name = attribs.name,
  }
  for k, v in pairs(attribs) do
    local key = k:match '^fig%-(%a%w*)$'
    if key then
      fig_attr[key] = v
    end
  end
  return {
    ['alt'] = pandoc.utils.blocks_to_inlines(caption),
    ['caption'] = caption,
    ['fig-attr'] = fig_attr,
    ['filename'] = attribs.filename,
    ['image-attr'] = {
      height = attribs.height,
      width = attribs.width,
      style = attribs.style,
    },
  }
end

-- Executes each document's code block to find matching code blocks:
local function code_to_figure (block)
  -- Check if a converter exists for this block. If not, return the block
  -- unchanged.
  local diagram_type = block.classes[1]
  local engine, linecomment_start = table.unpack(diagram_engines[diagram_type])
  if not engine then
    return nil
  end

  -- Call the converter
  local additional_packages =
    block.attributes['additional-packages'] or
    block.attributes["additionalPackages"]
  local success, img, imgtype = pcall(engine, block.text, additional_packages)

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

  -- Unified properties.
  local props = diagram_properties(block, linecomment_start)

  -- Use the block's filename attribute or create a new name by hashing the
  -- image content.
  local basename, _extension = pandoc.path.split_extension(
    props.filename or pandoc.sha1(img)
  )
  local fname = basename .. '.' .. extension_for_mimetype(imgtype)

  -- Store the data in the media bag:
  pandoc.mediabag.insert(fname, imgtype, img)

  -- Create a figure that contains just this image.
  local img_obj = pandoc.Image(props.alt, fname, "", props['image-attr'])
  return pandoc.Figure(pandoc.Plain{img_obj}, props.caption, props['fig-attr'])
end

function Pandoc (doc)
  configure(doc.meta)
  return doc:walk {
    CodeBlock = code_to_figure,
  }
end

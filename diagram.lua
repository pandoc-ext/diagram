--[[
diagram-generator – create images and figures from code blocks.

This Lua filter is used to create images with or without captions from
code blocks. Currently Asymptote, GraphViz, PlantUML, and Tikz can be
processed. For further details, see README.md.

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
local stringify = utils.stringify
local with_temporary_directory = system.with_temporary_directory
local with_working_directory = system.with_working_directory

--- Returns a filter-specific directory in which cache files can be
--- stored, or nil if no such directory is available.
local function cachedir ()
  local cache_home = os.getenv 'XDG_CACHE_HOME'
  if not cache_home or cache_home == '' then
    local user_home = system.os == 'windows'
      and os.getenv 'USERPROFILE'
      or os.getenv 'HOME'

    if not user_home or user_home == '' then
      return nil
    end
    cache_home = pandoc.path.join{user_home, '.cache'} or nil
  end

  -- Create filter cache directory
  return pandoc.path.join{cache_home, 'pandoc-diagram-filter'}
end

--- Path holding the image cache, or `nil` if the cache is not used.
local image_cache = nil

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
        execpath = key
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

  -- cache for image files
  if conf.cache ~= false then
    image_cache = conf['cache-dir']
      and stringify(conf['cache-dir'])
      or cachedir()
    pandoc.system.make_directory(image_cache, true)
  end
end

-- Call plantuml with some parameters (cf. PlantUML help):
local function plantuml (cb)
  local puml = cb.text
  local args = {"-tsvg", "-pipe", "-charset", "UTF8"}
  return pandoc.pipe(path['plantuml'], args, puml), 'image/svg+xml'
end

-- Call dot (GraphViz) in order to generate the image
-- (thanks @muxueqz for this code):
local function graphviz (cb)
  local code = cb.text
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
local function tikz (codeblock, additional_packages)
  local src = codeblock.text
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

--
-- Asymptote
--

local function asymptote(codeblock)
  local code = codeblock.text
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

local mimetype_for_extension = {
  pdf = 'application/pdf',
  png = 'image/png',
  svg = 'image/svg+xml',
}

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
local diagram_engines = setmetatable(
  {
    asymptote = {asymptote, '%%'},
    dot       = {graphviz, '//'},
    graphviz  = {graphviz, '//'},
    plantuml  = {plantuml, "'"},
    tikz      = {tikz, '%%'},
  },
  {
    __index = function (tbl, diagtype)
      local success, result = pcall(require, 'diagram-' .. diagtype)
      if success and result then
        tbl[diagtype] = result
        return result
      else
        -- do not try this again
        tbl[diagtype] = false
        return nil
      end
    end
  }
)

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

local function get_cached_image (codeblock)
  for _, ext in ipairs{'pdf', 'svg', 'png'} do
    local filename = pandoc.sha1(codeblock.text) .. '.' .. ext
    local imgpath = pandoc.path.join{image_cache, filename}
    local success, imgdata = pcall(read_file, imgpath)
    if success then
      return imgdata, mimetype_for_extension[ext]
    end
  end
  return nil
end

local function cache_image (codeblock, imgdata, mimetype)
  -- do nothing if caching is disabled or not possible.
  if not image_cache then
    return
  end
  local ext = extension_for_mimetype(mimetype)
  local filename = pandoc.sha1(codeblock.text) .. '.' .. ext
  local imgpath = pandoc.path.join{image_cache, filename}
  write_file(imgpath, imgdata)
end

-- Executes each document's code block to find matching code blocks:
local function code_to_figure (block)
  -- Check if a converter exists for this block. If not, return the block
  -- unchanged.
  local diagram_type = block.classes[1]
  if not diagram_type then
    return nil
  end

  local engine, linecomment = table.unpack(diagram_engines[diagram_type])
  if not engine then
    return nil
  end

  -- Try to retrieve the image data from the cache.
  local img, imgtype = get_cached_image(block)

  if not img or not imgtype then
    -- No cached image; call the converter
    local additional_packages =
      block.attributes['additional-packages'] or
      block.attributes["additionalPackages"]
    local success
    success, img, imgtype = pcall(engine, block, additional_packages)

    -- Bail if an error occured; img contains the error message when that
    -- happens.
    if not success then
      warn(PANDOC_SCRIPT_FILE, img)
      return nil
    elseif not img then
      warn(PANDOC_SCRIPT_FILE, 'Diagram engine returned no image data.')
      return nil
    elseif not imgtype then
      warn(PANDOC_SCRIPT_FILE, 'Diagram engine did not return a MIME type.')
      return nil
    end

    -- If we got here, then the transformation went ok and `img` contains
    -- the image data.
    cache_image(block, img, imgtype)
  end

  -- Convert SVG if necessary.
  if imgtype == 'application/pdf' and not format_accepts_pdf_images(FORMAT) then
    img, imgtype = pdf2svg(img), 'image/svg+xml'
  end

  -- Unified properties.
  local props = diagram_properties(block, linecomment)

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

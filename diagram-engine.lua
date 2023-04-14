local setmetatable = setmetatable

_ENV = {}

local DiagramEngine = {}



local function pipable_engine (config)
  return function (code, filetype)
    return pandoc.pipe(
      config.path,
      config.args(filetype),
      code
    )
  end
end

local graphvis = pipeable_engine{
  path = os.getenv 'DOT' or 'dot',
  args = function (filetype)
    return {'-T' .. filetype}
  end,
}

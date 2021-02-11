{ lib, ... }:
with lib;
rec {
  # vim dictionaries are, in theory, compatible with JSON
  toVimDict = args: toJSON 
    (lib.filterAttrs (n: v: !isNull v) args);

  # Black functional magic that converts a bunch of different Nix types to their
  # lua equivalents!
  toLuaObject = args:
    if builtins.isAttrs args then
      "{" + (concatStringsSep ","
        (mapAttrsToList
          (n: v: "[${toLuaObject n}] = " + (toLuaObject v))
        (filterAttrs (n: v: !isNull v || v == {}) args))) + "}"
    else if builtins.isList args then
      "{" + concatMapStringsSep "," toLuaObject args + "}"
    else if builtins.isString args then
      # This should be enough!
      escapeShellArg args
    else if builtins.isBool args then
      "${ boolToString args }"
    else if builtins.isFloat args then
      "${ toString args }"
    else if builtins.isInt args then
      "${ toString args }"
    else if isNull args then
      "nil"
    else "";

  # Generates maps for a lua config
  genMaps = mode: maps: let
    normalized = builtins.mapAttrs (key: action:
      if builtins.isString action then
        {
          silent = false;
          expr = false;
          unique = false;
          noremap = true;
          script = false;
          nowait = false;
          action = action;
        }
      else action) maps;
  in builtins.attrValues (builtins.mapAttrs (key: action:
    {
      action = action.action;
      config = lib.filterAttrs (_: v: v) {
        inherit (action) silent expr unique noremap script nowait;
      };
      key = key;
      mode = mode;
    }) normalized);

  # Creates an option with a nullable type that defaults to null.
  mkNullOrOption = type: desc: lib.mkOption {
    type = lib.types.nullOr type;
    default = null;
    description = desc;
  };

  mkPlugin = { config, lib, ... }: {
    name,
    description,
    extraPlugins ? [],
    options ? {},
    ...
  }: let
    cfg = config.programs.nixvim.plugins.${name};
    # TODO support nested options!
    pluginOptions = mapAttrs (k: v: v.option) options;
    globals = mapAttrs' (name: opt: {
      name = opt.global;
      value = if cfg.${name} != null then opt.value cfg.${name} else null;
    }) options;
  in {
    options.programs.nixvim.plugins.${name} = {
      enable = mkEnableOption description;
    } // pluginOptions;

    config.programs.nixvim = mkIf cfg.enable {
      inherit extraPlugins globals;
    };
  };

  globalVal = val: if builtins.isBool val then
    (if val == false then 0 else 1)
  else val;

  mkDefaultOpt = { type, global, description ? null, example ? null, value ? v: toLuaObject (globalVal v), ... }: {
    option = mkOption {
      type = types.nullOr type;
      default = null;
      description = description;
      example = example;
    };

    inherit value global;
  };
}

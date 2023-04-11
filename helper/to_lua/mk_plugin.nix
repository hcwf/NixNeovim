{ customOptions
, camelToSnake
, config
, lib
, indent
, toLuaObject
}:

# helper function to create a lua based plugin # TODO: make usable with non-lua plugins

let

  # imports

 inherit (lib)
    assertMsg
    hasAttr
    hasPrefix
    mapAttrs'
    mkIf
    nameValuePair
    optionalString
    replaceStrings
    stringLength
    types
    mkOption
    warnIf;

  # internal functions

  # converts the module options to lua code and
  # adds the 'extraAttrs'
  convertModuleOptions = cfg: moduleOptions:
    let
      attrs = mapAttrs' (k: v: nameValuePair (camelToSnake k) (cfg.${k})) moduleOptions;
      extraAttrs = mapAttrs' (k: v: nameValuePair (camelToSnake k) v) cfg.extraConfig;
    in
    attrs // extraAttrs;

  # helper function to check if the given url is valid
  validUrl = url:
      hasPrefix "https://" url;

  # These module options are addded to every module
  defaultModuleOptions = description: {
    enable = customOptions.boolOption false description;
    extraConfig = mkOption {
      # this is added to lua in 'convertModuleOptions'
      type = types.attrsOf types.anything;
      default = { };
      description = "Place any extra config here as an attibute-set";
    };
    extraLua = {
      pre = mkOption {
        type = types.str;
        default = "";
        description = "Place any extra lua code here that is loaded before the plugin is loaded";
      };
      post = mkOption {
        type = types.str;
        default = "";
        description = "Place any extra lua code here that is loaded after the plugin is loaded";
      };
    };
  };

in {

  # Exported functions
  inherit convertModuleOptions defaultModuleOptions;

  mkLuaPlugin = { name                  # name of the plugin module
  , pluginName ? name     # name of the plugin as it appears in 'require("<pluginName>")' if different
  , pluginUrl ? ""        # link to plugin project page
  , extraPlugins          # plugin packages
  , description ? ""      # deprecated, use extraDescription
  , extraDescription ? "" # description added to the enable function
  , extraPackages ? [ ]   # non-plugin packages
  , extraConfigLua ? null # lua config added to the init.vim
  , extraConfigVim ? ""   # vim config added to the init.vim
  , moduleOptions ? { }   # options available in the module
  , defaultRequire ? true # add default requrie string?
  , extraOptions ? {}     # extra vim options like line numbers, etc
  }:
  let
    # simple functions to improve error messages
    errorString = "Module for ${name} is broken";
    warnString = "Module for ${name}";

    cfg = config.programs.nixneovim.plugins.${name};

    pluginOptions = convertModuleOptions cfg moduleOptions;

    fullDescription =
      warnIf (description != "") "${warnString}: 'description' is deprecated, please use extraDescription"
      warnIf (!validUrl pluginUrl) "${warnString}: Please add the 'pluginUrl' (like 'https://...')" (
      let
        link = if validUrl pluginUrl then
          "<link xlink:href=\"${pluginUrl}\">${name}</link>"
        else name; # if no link given
      in
      ''
        Enable the ${link} plugin. </para><para>

        ${extraDescription}
      '');

    # add default require string to load plugin
    luaConfig = optionalString defaultRequire (if (extraConfigLua == null) then
      "require('${pluginName}').setup ${toLuaObject pluginOptions}"
    else extraConfigLua);

  in

  # assert assertMsg (extraPlugins != []) "${errorString}: no plugin specified 'extraPlugins'"; # FIX: this somehow results in infinite recursion
  assert assertMsg (stringLength name > 0) " ${errorString}: 'name' is empty";
  assert assertMsg (!hasAttr "enable" moduleOptions) "${errorString}: Please remove the 'enable' options. This is added by 'mkLuaPLugin' automatically";

  # function output
  {
    options.programs.nixneovim.plugins.${name} =
      (defaultModuleOptions fullDescription) // moduleOptions;

    config.programs.nixneovim = mkIf cfg.enable {
      inherit extraPlugins extraPackages extraConfigVim;

      extraConfigLua = optionalString
        (cfg.extraLua.pre != "" || cfg.extraLua.post != "" || luaConfig != "")
        ''

        -- config for plugin: ${name}
        do
          function setup()
            ${cfg.extraLua.pre}
            ${replaceStrings ["\n"] ["\n${indent 2}"] luaConfig}
            ${cfg.extraLua.post}
          end
          success, output = pcall(setup) -- execute 'setup()' and catch any errors
          if not success then
            print(output)
          end
        end
      '';
      options = extraOptions;
    };
  };
}
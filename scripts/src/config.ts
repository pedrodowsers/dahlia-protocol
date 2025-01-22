// config.ts
import fs from "fs";
import yaml from "js-yaml";
import _ from "lodash";
import moment from "moment";
import sh from "shelljs";

// A minimal interface for your top-level config structure.
// Feel free to refine based on your actual config schema.
export interface Config {
  [key: string]: any;
  environments?: {
    static?: string[];
    default?: string;
  };
}
const timestamp = moment().format("YYYYMMDDHHmmss");

// These variables will be set/updated within the load() process.
let multiFile = false;
let envId: string | undefined;
let ENVID: string | undefined;
let environmentType: string | undefined;
let environmentTypes: string[] | undefined;
let environments: Record<string, any>;
let config: Config;

export const configName = "configs/default.yml";
export const configDeployedName = (remote?: boolean) => (remote ? "configs/remote.yml" : "configs/docker.yml");

/**
 * Loads and returns a config object, resolving environment and variable substitutions.
 * @param env - An optional environment override (e.g. 'dev', 'stage', 'prod', etc.)
 * @param deployedContracts - additional contracts already deployed
 */
export function load(env?: string, deployedContracts?: Config): Config {
  config = _.merge({}, loadConfigFile(configName), deployedContracts);
  environments = config.environments || Object();

  envId = getEnvId(config, env);
  ENVID = envId ? envId.toUpperCase() : undefined;

  // If config.environments has a 'static' array, treat that as valid environment types;
  // otherwise, fall back to the top-level keys of config.
  environmentTypes = environments.static || (_.keys(config) as string[]);
  environmentType = _.includes(environmentTypes, envId) ? envId : environments.default;

  // Perform variable substitution
  config = swapVariables(config);
  return config;
}

export function loadConfigFile(file: string): Config {
  if (fs.existsSync(file)) {
    const fileContents = fs.readFileSync(file, "utf8");
    return yaml.load(fileContents, { filename: file }) as Config;
  } else {
    return {};
  }
}

export function saveConfigFile(file: string, config: Config): void {
  fs.writeFileSync(file, yaml.dump(config, { sortKeys: true }));
}

/**
 * Attempt to guess the environment ID from the current git branch.
 */
function getEnvIdFromBranch(): string | undefined {
  try {
    let branch = sh.exec("git name-rev HEAD --name-only", { silent: true }).stdout;
    branch = _.last(_.split(branch, "/")) || "";
    return _.trimEnd(
      _.truncate(branch, {
        length: 13,
        omission: "",
      }),
      "-",
    ).replace(/(\r\n|\n|\r)/gm, "");
  } catch (e) {
    console.log("ERR: ", e);
    // Do nothing
  }
  return undefined;
}

/**
 * Determines the effective environment ID from function args, CLI args,
 * environment variables, or the git branch name (in that order).
 */
function getEnvId(obj: Config, env?: string): string | undefined {
  return (
    env ||
    // (yargs(hideBin(process.argv)).argv as string | undefined) ||
    // _.flow(_.pick(_.keys(obj)), _.keys, _.head)(yargs.argv) ||
    // process.env.ENVIRONMENT_ID ||
    getEnvIdFromBranch()
  );
}

interface SubstituteResult {
  success: boolean;
  replace: string;
}

/**
 * Substitute strings of the form ${someKey} with values found in `file[someKey]`.
 */
function substitute(file: Config, p: string): SubstituteResult {
  let success = false;
  const replaced = p.replace(/\${([\w.-]+)}/g, (match, term) => {
    let replacement = _.get(file, term);
    if (replacement === undefined) {
      // Then check environment variables
      replacement = process.env[term];
    }

    // If we found a replacement in either config or environment, mark success
    if (replacement !== undefined) {
      success = true;
      return String(replacement);
    } else {
      // Leave as-is if not found anywhere
      return match;
    }
  });
  return { success, replace: replaced };
}

interface TransformResult {
  changed: boolean;
  result: any;
}

/**
 * Recursively walk the `obj` to substitute string patterns from `file`.
 */
function transform(file: Config, obj: any): TransformResult {
  let changed = false;
  const resultant = _.mapValues(obj, (p: any) => {
    if (_.isPlainObject(p)) {
      const transformed = transform(file, p);
      if (!changed && transformed.changed) {
        changed = true;
      }
      return transformed.result;
    }

    if (_.isString(p)) {
      const subbed = substitute(file, p);
      if (!changed && subbed.success) {
        changed = true;
      }
      return subbed.replace;
    }

    if (_.isArray(p)) {
      for (let i = 0; i < p.length; i++) {
        if (_.isPlainObject(p[i])) {
          const transformed = transform(file, p[i]);
          if (!changed && transformed.changed) {
            changed = true;
          }
          p[i] = transformed.result;
        }
        if (_.isString(p[i])) {
          p[i] = substitute(file, p[i]).replace;
        }
      }
    }
    return p;
  });
  return { changed, result: resultant };
}

/**
 * Prints the currently loaded environment details.
 */
export function log(): void {
  console.log("CONFIG:", envId || "-", environmentType || "-");
}

/**
 * Ensures that the specified settings exist in the loaded config object.
 * If any are missing, throws an Error.
 */
export function requireSettings(settings: string | string[]): void {
  const erredSettings: string[] = [];
  const requiredKeys = _.isString(settings) ? [settings] : settings;

  _.forEach(requiredKeys, (setting) => {
    if (!_.has(config, setting)) {
      erredSettings.push(setting);
    }
  });

  if (erredSettings.length > 1) {
    throw new Error("The following settings are required in config.yml: " + erredSettings.join("; "));
  }

  if (erredSettings.length === 1) {
    throw new Error(erredSettings[0] + " is required in config.yml");
  }
}

/**
 * Performs multiple passes of string substitution until no more substitutions occur,
 * then merges environment-specific config on top of the base config.
 */
function swapVariables(configFile: Config): Config {
  function readAndSwap(obj: Config): Config {
    let altered: boolean;
    let swapped = obj;

    do {
      const temp = transform(swapped, swapped);
      swapped = temp.result;
      altered = temp.changed;
    } while (altered);

    return swapped;
  }

  // If multiFile is true, we process each key in the config object individually
  let file: any = multiFile ? _.mapValues(configFile, readAndSwap) : configFile;

  // Merge environment-specific sections + some dynamic fields
  file = _.merge({}, file, file[environmentType ?? ""] || {}, {
    envId,
    ENVID,
    timestamp,
  });

  // Final read-and-swap pass across the merged object
  file = readAndSwap(file);
  return file;
}

// Load immediately so that `import config from './config'` returns the result
const defaultExport = load();
export default defaultExport;

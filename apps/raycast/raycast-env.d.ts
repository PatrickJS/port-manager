/// <reference types="@raycast/api">

/* 🚧 🚧 🚧
 * This file is auto-generated from the extension's manifest.
 * Do not modify manually. Instead, update the `package.json` file.
 * 🚧 🚧 🚧 */

/* eslint-disable @typescript-eslint/ban-types */

type ExtensionPreferences = {}

/** Preferences accessible in all the extension's commands */
declare type Preferences = ExtensionPreferences

declare namespace Preferences {
  /** Preferences accessible in the `list-ports` command */
  export type ListPorts = ExtensionPreferences & {}
  /** Preferences accessible in the `find-port` command */
  export type FindPort = ExtensionPreferences & {}
  /** Preferences accessible in the `menu-bar` command */
  export type MenuBar = ExtensionPreferences & {}
}
declare namespace Arguments {
  /** Arguments passed to the `list-ports` command */
  export type ListPorts = {}
  /** Arguments passed to the `find-port` command */
  export type FindPort = {
  /** 3000 */
  "port": string
}
  /** Arguments passed to the `menu-bar` command */
  export type MenuBar = {}
}

# Changelog for Pure Data auto completion tcl plugin

## v0.44.0 (Henri Augusto)

* *Major* overhaul and bugfix to the code to bring it up to working condition in par with pd 0.48 API.
* Now the plugin seems to be working on Windows, Linux and OSX!

### new features

* now you can configure the plugin under preferences->PD AutoComplete Settings
* Now *::completion::read_config* ignores any line that doesn't start with a char. 
* While reading the cfg file it reads lists of arguments instead of just one. Pprevents reading "DejaVu" instead of "DejaVu Sans Mono", for example.
* Now the plugin is able to run witout the .cfg file. It creates the .cfg file in it's absence
* I've implemented three search modes
    * **normal:** search for exact matches
    * **skip:** search for anything containing the input chars in order. Ex: plf matches zexy/[p]o[l]y[f]un
    * **monolithic:** search for objects contained in monolithic distributions (.dll, pd_darwin, .pdlinux). Those need to be declared in monolithicLibs.txt.
* Each search mode has a color
* The plugin intelligently scans the paths set by the user (edit->preferences->path) to scan for externals without the need for the user to type their name on a file. Consequently the script doesn't need a list of objects. 
* Yet you can still define useful stuff in any .txt inside the folder *custom_completions*. I've already added some useful keywords like 'anything', 'adddollar', etc and even some constants like Pi and the golden ratio.
* Added navigating faster with shift+up/down
* added warping the listbox ends (overriding the bindings)
* If the completions window would be drawed off-screen we adjust it's position so it is enterily visible.
* I'm disabling the unique names completion for now because i don't think it is desireable. While it does detects when the user type a new name it **doesn't** when those names are not used any more (user closed their containing patch, deleted their objects, etc). In future versions we should be able to do that communicating with PD directly.
* Flexible debugging options (see development guide.md)



## Yvan Volochine version history: 

![original project on GitHub](https://github.com/gusano/

## v0.43

 - new BSD License


## 0.42:

 - add `user_objects` file support
 - add optional offset for popup position
 - add forgotten drawpolygon

## 0.41:

 - cleanup, simplify focus behavior, remove unused proc, better bindings
 - add support to remember `send, receive, table, delread, ...` argument names
 - add libraries objects lists (Gem, gridflow, py)
 - various fixes

## 0.40:

 - new GUI
 - rename to 'completion-plugin.tcl'
 - add bash completion mode
 - add support for osx and win32
 - add *.cfg file for user options
 - TODO add support for user arguments (like [tabread foo], etc) ??

## 0.33:

 - cosmetic fixes for osx
 - better box coordinates
 - bugfix: popup menu wrongly placed with huge fonts

## 0.32:

 - add colors
 - bugfix: cycling has 1 step too much
 - bugfix: first completed doesn't erase typed text

## 0.31:

 - add TAB support to cycle through completions

## 0.3:

 - simplify cycling code
 - bugfix: nameclash with right-click popup (sic)
 - bugfix: missing or mispelled internals

## 0.2:

 - add popup menu for completion

## 0.12:

 - fix namespace
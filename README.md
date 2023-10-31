# AMX IP Manager
Managing IP connections in AMX

## Why?
I've seen code where TCP connections were opened and closed in a button push. Some people seem to have problems using the low level IP commands. So here is my IP Manager!

## How to use IP Manager
I've included `main.axs` as demo having some snippets and comments. You should have a look into `ip_manager.axi` too to know the relevant functions and signatures. It should be straight forward and easy.  
Since we're changing a lot of variables, don't use instructions in `DEFINE_START`. You shoud generally don't do that to avoid boot loops.

### Variable dev mode
There's a cool mode of this module which allows device definition being created automatically into DEV variables. Different include files can create IP connections independently without overlapping D:P:S definitions. Works great but unfortunately it's not compatible with `CREATE_BUFFER`.  
You can enable the variable mode with a compile switch before including the IP Manager:  
`#DEFINE ip_manager_variable_devs`


## Community version
AMX NetLinx is poor in modularity and in reusing code. I really miss OOP.  
So this is a modified stand alone version of my original _ip_manager.axi, which is heavily integrated in my AMX project eco system.  
I've moved a few very common functions in common.axi such as logging. It should be quite easy to adopt it to your coding style.


## Panel integration
Similar to the IP Manager I have a panel manager. **But I've commented out these function calls in the IP Manager**. Connection status could be displayed directly into a button feedback.  
Feel free to adopt the panel integration. I've included `_panel.axi` if you're curious and want to extract missing functions which are commented out. But that file it's **not required** for this version of IP Manager. You would basically need a `DEV panel[]` array variable (or constant) and define some array bounds like this:
```
INTEGER panels_max = 4 // for memory optimization. Reserve some spare.
INTEGER rooms_max = 2 // maximal number of rooms or areas
```
My eco system is designed to add panels without huge modifications. Each panel is also assigned to a specific room or region and can be changed dynamically.

## My AMX eco system
Since AMX NetLinx is old and poor in useful features like object oriented programming, pointers, memory access, etc., which would make programming more fun and more flexible, it's mandatory to work with a lot of global variables and name them properly. Even the include order is sometimes tricky and annoying.  
May be you'll see more of my modules in the future.
Each of my modules are prefixed with an underscore like `_panel.axi` and is meant to be read only and resides in a common directory for all projects. Having multiple copies of different versions of a module per project can be confusing. Hint: You already get a copy in your `*.src` file.
My main goal is to keep the `main.axs` small and declarative. All main logic like volume control is handled in the background and `main.axs` only includes drivers and basically connects their functions to buttons.

## Modules
By "modules" I mostly refer to **include files** `*.axi` instead of NetLinx modules. I use modules for simple and good reasons only. And I often ship a supplementary axi file for the module.

### Modules contra
- No easy configuration with constants in the `DEFINE_MODULE` line. Only variables allowed.
- No call of complex functions with parameters possible. You have to serialize it into strings and deserialize it back in the module. This is NOT a good convention.
- Modules may be binary only, without source code

### Modules pro
- Isolated namespace for variables which do not collide with the main program.
- Events like Online, Offline or even Button press emulation is possible.

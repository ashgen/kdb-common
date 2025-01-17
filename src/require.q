// Code Loading Library
// Copyright (c) 2016 - 2017 Sport Trades Ltd, (c) 2020 - 2021 Jaskirat Rajasansir

// Documentation: https://github.com/BuaBook/kdb-common/wiki/require.q

/ The file suffixes that are supported for a library
.require.fileSuffixes:(".q";".k";".*.q";".*.k";".q_";".*.q_");

/ Table containing the state of each library loaded via require
.require.loadedLibs:`lib xkey flip `lib`loaded`loadedTime`inited`initedTime`files!"SBPBP*"$\:();

/ Root folder to search for libraries
.require.location.root:`;

/ Regexs to filter discovered files
/  @see .require.i.tree
.require.location.ignore:("*.git";"*target");

/ Complete list of discovered files from the root directory
.require.location.discovered:enlist`;

/ Required interface implementations for 'require' and related kdb-common libraries to function correctly
.require.interfaces:`lib`ifFunc xkey flip `lib`ifFunc`implFunc!"SS*"$\:();
.require.interfaces[``]:(::);
.require.interfaces[`log`.log.if.trace]:`.require.i.log;
.require.interfaces[`log`.log.if.debug]:`.require.i.log;
.require.interfaces[`log`.log.if.info]: `.require.i.log;
.require.interfaces[`log`.log.if.warn]: `.require.i.log;
.require.interfaces[`log`.log.if.error]:`.require.i.logE;
.require.interfaces[`log`.log.if.fatal]:`.require.i.logE;


.require.init:{[root]
    if[.require.loadedLibs[`require]`inited;
        .log.if.trace "Require is already initialised. Will ignore request to init again";
        :(::);
    ];

    $[null root;
        .require.location.root:.require.i.getCwd[];
        .require.location.root:root
    ];

    .require.i.setDefaultInterfaces[];

    (.require.markLibAsLoaded;.require.markLibAsInited)@\:`require;

    / If file tree has already been specified, don't overwrite
    if[.require.location.discovered~enlist`;
        .require.rescanRoot[];
    ];

    .require.i.initInterfaceLibrary[];

    .log.if.info "Require library initialised [ Root: ",string[.require.location.root]," ]";
 };


/ Loads the specified library but does not initialise it. Useful if there is some configuration
/ to perform after load, but prior to initialisation. When you are ready to to initialise,
/ use .require.lib.
/  @see .require.i.load
.require.libNoInit:{[lib]
    if[lib in key .require.loadedLibs;
        :(::);
    ];

    .require.i.load lib;
 };

/ Loads the specified libary and initialises it. Checks loaded and initialised state to prevent
/ reload or re-init if already performed.
/  @see .require.i.load
/  @see .require.i.init
.require.lib:{[lib]
    if[lib in key .require.loadedLibs;
        $[.require.loadedLibs[lib]`inited;
            :(::);
            :.require.i.init lib
        ];
    ];

    (.require.i.load;.require.i.init)@\:lib;
 };

.require.rescanRoot:{
    .require.location.discovered:.require.i.tree .require.location.root;

    .log.if.info "Library root location refreshed [ File Count: ",string[count .require.location.discovered]," ]";
 };

/ Marks the specified library as loaded in the loaded libraries table. NOTE: This
/ function does not actually do the load
/  @see .require.loadedLibs
.require.markLibAsLoaded:{[lib]
    .require.loadedLibs[lib]:`loaded`loadedTime!(1b;.z.P);
 };

/ Marks the specified library as initialised in the loaded libraries table. NOTE:
/ This function does not actually do the init
/  @see .require.loadedLibs
.require.markLibAsInited:{[lib]
    .require.loadedLibs[lib]:`inited`initedTime!(1b;.z.P);
 };


/ Attempts to load the specified library
/  @throws LibraryDoesNotExistException If no files are found for the specified library
/  @throws LibraryLoadException If any of the library files fail to load
.require.i.load:{[lib]
    .log.if.info "Loading library: ",string lib;

    libFiles:.require.i.findFiles[lib;.require.location.discovered];

    if[0~count libFiles;
        .log.if.error "No files found for library [ Lib: ",string[lib]," ]";
        '"LibraryDoesNotExistException (",string[lib],")";
    ];

    {
        .log.if.info "Loading ",x;
        loadRes:@[system;"l ",x;{ (`LOAD_FAILURE;x) }];

        if[`LOAD_FAILURE~first loadRes;
            .log.if.error "Library file failed to load! [ File: ",x," ]. Error - ",last loadRes;
            '"LibraryLoadException";
        ];
    } each 1_/:string libFiles;

    .require.markLibAsLoaded lib;
    .require.loadedLibs[lib]:enlist[`files]!enlist libFiles;
 };

/ Searchs for files with the specified library prefix in the source folder supplied
/  @see .require.fileSuffixes
.require.i.findFiles:{[lib;files]
    filesNoPath:last each ` vs/:files;
    :files where any filesNoPath like/: string[lib],/:.require.fileSuffixes;
 };

/ Performs the initialisation of the specified library. Assumes .*lib*.init[]. Also checks for
/ .*lib*.*stack*.init[] and executes if exists (if not present, ignored).
/  @throws UnknownLibraryException If the library is not loaded
/  @throws LibraryInitFailedException If the init function throws an exception
.require.i.init:{[lib]
    if[not lib in key .require.loadedLibs;
        '"UnknownLibraryException";
    ];

    initFname:` sv `,lib,`init;
    initF:@[get;initFname;`NO_INIT_FUNC];

    if[not `NO_INIT_FUNC~initF;
        .log.if.info "Library initialisation function detected [ Func: ",string[initFname]," ]";

        / If in debug mode, execute init function without try/catch
        $[`boolean$system"e";
            initRes:initF (::);
            initRes:@[initF;::;{ (`INIT_FUNC_ERROR;x) }]
        ];

        if[`INIT_FUNC_ERROR~first initRes;
            .log.if.error "Init function (",string[initFname],") failed to execute successfully [ Lib: ",string[lib]," ]. Error - ",last initRes;
            '"LibraryInitFailedException (",string[initFname],")";
        ];

        .require.markLibAsInited lib;

        .log.if.info "Initialised library: ",string lib;
    ];
 };

/ @returns (FolderPath) The current working directory using the OS specific command
/ @throws OsNotSupportedForCwdException If the operating system is not supported
.require.i.getCwd:{
    os:first string .z.o;

    if["w"~os;
        :hsym first `$trim system "echo %cd%";
    ];

    if[os in "lms";
        :hsym first `$trim system "pwd";
    ];

    '"OsNotSupportedForCwdException (",string[.z.o],")";
 };

.require.i.tree:{[root]
    rc:` sv/:root,/:key root;
    rc:rc where not any rc like\:/:.require.location.ignore;

    folders:.require.i.isFolder each rc;

    :raze (rc where not folders),.z.s each rc where folders;
 };

.require.i.isFolder:{[folder]
    :(not ()~fc) & not folder~fc:key folder;
 };

/ Set the default interface implementations before the Interface library (if) is available
/  @see .require.interfaces
.require.i.setDefaultInterfaces:{
    interfaces:0!delete from .require.interfaces where null[lib] | null ifFunc;

    (set)./: flip interfaces`ifFunc`implFunc;
 };

/ Initialise and defer interface management to the Interface library (if)
/  @see .require.interfaces
/  @see .if.setImplementationsFor
.require.i.initInterfaceLibrary:{
    .require.libNoInit`if;

    requiredIfs:0!`lib xgroup .require.interfaces;

    { .if.setImplementationsFor[x`lib; flip `lib _ x] } each requiredIfs;

    .require.lib`if;
 };

/ Supports slf4j-style parameterised logging for improved logging performance even without a logging library
/  @param (String|List) If a generic list is provided, assume parameterised and replace "{}" in the message (first element)
/  @returns (String) The message with "{}" replaced with the values supplied after the message
.require.i.parameterisedLog:{[message]
    if[0h = type message;
        message:"" sv ("{}" vs first message),'(.Q.s1 each 1_ message),enlist "";
    ];

    :message;
 };

/ Standard out logger
.require.i.log: ('[-1; .require.i.parameterisedLog]);

/ Standard error logger
.require.i.logE:('[-2; .require.i.parameterisedLog]);

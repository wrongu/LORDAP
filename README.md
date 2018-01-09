Load-Or-Run Data-Analysis Pipeline (LORDAP)
===

LORDAP is designed for people who

- have an existing Matlab data-processing "pipeline" - a set of functions that transform data to figures and statistics
- are tired of waiting for big computations to run
- find it tedious to keep track of files storing partially computed results
- don't have the resources to learn or implement a more fully-featured pipeline system

__If you are designing a new pipeline from scratch, this is probably not the system for you!__ See "Choosing Between Pipeline Management Systems" below for a comparison with other systems.

Building "top-down" pipelines
---

The core philosophy of LORDAP is that the interface to your data should be "top-down." In other words, users should interface with plotting functions, and "heavy-lifting" functions should have their outputs cached. A high-level function like `plotTrend()` would then call a sister function `computeTrend()`, which may itself call other sub-routines like `computeA()` and `computeB()`. Graphically, the dependencies would look like this:

```
plotTrend
 - computeTrend
   - computeA
   - computeB
```

By wrapping each of the `compute` functions with `loadOrRun`, they only ever need to be computed once. Subsequent calls to `plotTrend` will load cached outputs of `computeTrend`. If you have another function `computeX` that calls `computeA`, then `computeA` will not have to be called again.

Choosing Between Pipeline Management Systems
---

If you're designing a pipeline from scratch, consider using [DataJoint](https://datajoint.io) or [PSOM](http://psom.simexp-lab.org/).

| | DataJoint | PSOM | LORDAP |
| -------------- | ------------- | ------------- | ------------- |
| Backend/infrastructure | MySQL server* | any filesystem | any filesystem |
| Learning Curve | steep | moderate | easy |
| Support & docs | full-time | [forum](https://www.nitrc.org/forum/forum.php?forum_id=1316) | minimal (Github issues) |
| Language(s) | Matlab/Python | Matlab/Octave | Matlab/Octave |
| Parallel/cluster tools | tracks jobs | automatic | none |
| "Caching" semantics | sort of | no | yes |
| "Drop in" to existing code | no | sort of | yes |

\* DataJoint will also host a server for you, for a fee

Feel free to [open an issue](https://github.com/wrongu/lorps/issues) here if you think another system should be added to this table.

Basic Usage
---

Let's say you have an expensive or time-consuming function `process_data`. Simply replace

```matlab
x = process_data(arg1, arg2, arg3);
```

with 

```matlab
x = loadOrRun(@process_data, {arg1, arg2, arg3});
```

and LORDAP will automatically cache the results of `process_data` in a file whose name is generated from the values of `arg1` through `arg3`.
Additional options help control exactly how a unique identifier (UID) is constructed from the given arguments. Or, to manually
specify the UID, pass in a third `options` struct with a `uid` field set to the desired name. For example,

```matlab
options.uid = '12345';
x = loadOrRun(@process_data, {arg1, arg2, arg3}, options);
```

which will create a cache file named `'process_data-12345.mat'` to store the results. Any further calls with the same `uid` will load the
cached result. When using the `uid` option, it is the responsibility of the user to ensure that different calls get different `uid`s when appropriate.

Advanced Usage and Default Arguments
---

LORDAP provides a set of options to manage how a UID is constructed from function arguments. See the documentation inside `loadOrRun.m`
for the full set of options. See [testLoadOrRun](testLoadOrRun.m) for some examples.

How UIDs are constructed is largely controlled using **default arguments**, set in the `options.defaultArgs` field. This is a cell array of the same size (or smaller) than the function's arguments specifying default values for the first `1..length(defaultArgs)` arguments. Wherever `defaultArgs` contains `[]`, the argument is ignored entirely (this means that `[]` **cannot** be used as an actual default). This logic is applied recursively to structs and cell arrays so that individual fields or elements in a cell array may have default values or be ignored while the rest are unaffected.

Cell arrays and long string fields that take on their default values will be replaced with `'default'` in the cached file's name. For struct arguments, fields with default values are omitted from the UID. See [testLoadOrRun](testLoadOrRun.m) for examples of how `args` and `defaultArgs` interact to form a UID. For most users, the details of exactly how filenames are generated is not important.

"Gotchas"
---

In Matlab, type `help loadOrRun` to see details and additional options. Briefly, be aware of the following:

* Fully integrating LORDAP into your project will require some small overhead:
    * create a centralized set of default arguments (usually in a struct) and pass options around between all functions.
    * it is common to see `loadOrRun(@myfunction, {options, arg1, arg2}, options)` so that `myfunction` has access to `options` as well, e.g. for passing it through to another call to `loadOrRun`. Then, simply have the first `defaultArgument` set to `[]` to ignore the actual value of `options`.
    * it is recommended that you periodically purge the directory of cached results, since cached file names will tend to grow stale as new features are added and arguments change.
* If your function has multiple outputs, you must use the `~` placeholder for any outputs you're not using at a given time. For example, if `f` has two outputs, use `[result, ~] = loadOrRun(@f, {}, ...)` so that `loadOrRun` knows to cache the second output as well for future calls.
* LORDAP will create files in your project (unless you configure outputs to be elsewhere). With the default options, you will want to add `.cache/` and `.meta/` to your `.gitignore` file.
* Unix filenames are limited to 255 characters. LORDAP will automatically and silently "hash" filenames longer than this. Warnings will be issued when there are hash collisions (which is extremely unlikely). However, hashed files cannot be easily searched in your filesystem - they will look something like `process_data-84D2F807.mat` - and should be avoided. Tips for reducing filename sizes:
    * use short function names
    * set `options.defaultString` to something short like `'X'`, `'_'`, or `'...'`
    * make use of `options.defaultArgs`, especially with struct arguments, so that default fields can be dropped from the filename.
* Be careful making changes to `options.defaultArgs`, as this may result in a mismatch between previously cached filenames and new results.
* LORDAP does not scale well, especially when arguments form complex "queries" for different subsets of a large dataset. [DataJoint](https://datajoint.io) is a better option in this situation, since it leverages the speed and scalability of a SQL database backend.
* Notes on how changed dependencies are handled (configured in `options.onDependencyChange`):
    * LORDAP uses modification timestamps on a `.m` file to detect when the associated data has become stale and should be deleted.
    * There are essentially two modes: ignore the problem completely or aggressively delete a cached result if there is any chance it needs updating (which may unnecessarily force other things to be recomputed later).
    * Avoid caching _local_ functions, since any change to the surrounding file will trigger the deletion of cached results. Each cached function should be given its own file.
    * LORDAP cannot tell the difference between functions with the same name in different packages when it comes to detecting changed dependencies. More specifically, if `+packageA/foo.m` depends on `bar.m`, __and__ there exists some other function named `foo` in another package like `+packageB/foo.m`, then a change to `bar.m` will trigger an update to `foo` both in package A (expected) package B (unexpected!). This has no real side effects except that `packageB.foo` may be recomputed more often than necessary.

License
---

[MIT](LICENSE.txt)

Note that this license should be copied and referenced alongside the source when using LORDAP in your project.

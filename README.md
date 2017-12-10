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
| Learning Curve | steep | moderate | low |
| Support/Documentation | full-time | [forum](https://www.nitrc.org/forum/forum.php?forum_id=1316) | minimal (Github issues) |
| Language(s) | Matlab/Python | Matlab/Octave | Matlab/Octave |
| Parallel/cluster tools | tracks jobs | automatic | none |
| "Caching" semantics | sort of | no | yes |
| "Drop in" to existing code | no | no | yes |

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
options.uid = '12345';  % Set unique identifier (uid) for caching filename
x = loadOrRun(@process_data, {arg1, arg2, arg3}, options);
```

and LORDAP will automatically cache the results of `process_data` in a file named `'process_data-12345.mat'`. By including parameter names in the unique
identifier (UID), you can cache the results for different arguments:

```matlab
options.uid = 'arg1=7';
x1 = loadOrRun(@process_other_data, {7}, options);
options.uid = 'arg1=12';
x2 = loadOrRun(@process_other_data, {12}, options);
```

...but even this can get tedious and can be automated using "query structs"

Advanced Usage and Query Structs
---

LORDAP provides a "query" mechanism to automatically construct UIDs from a "query struct." For example,

```matlab
q.arg1 = 7;
q.arg2 = 'a string';
options = struct('query', q);
x1 = loadOrRun(@process_other_data, {q.arg1, q.arg2}, options);
q.arg1 = 12;
options = struct('query', q);
x2 = loadOrRun(@process_other_data, {q.arg1, q.arg2}, options);
```

which will automatically generate a UID from `options.query`, in this case saving to `'process_other_data-arg1=7-arg2=a_string.mat'` and
`'process_other_data-arg1=12-arg2=a_string.mat'`. The fields of a query struct can be numeric (scalars or arrays), strings, cell arrays,
or other structs.

By design, LORDAP pays no attention to the actual arguments passed to the function. At first it seems reasonable that a function should be cached based on the arguments passed to it. However, arguments are often large, and 'uniqueness' of arguments depends on the context. For example, a function may take a large random array as input, but you only want to cache based on the seed that generated it. Using `options.uid` or `options.query` is a compromise that gives the user full control over how 'uniqueness' is defined, while remaining easy to use.

"Gotchas"
---

In Matlab, type `help loadOrRun` to see details and additional options. Briefly, be aware of the following:

* Fully integrating LORDAP into your project will require some small overhead:
    * at the "bottom" of the pipeline, write a loader function that will read raw data given a query struct
    * create a "default" query struct and  pass query structs around between all functions
    * periodically purge the directory of cached results, since cached file names will tend to grow stale as new query features are added.
* If your function has multiple outputs, you must use the `~` placeholder for any outputs you're not using at a given time. For example, if `f` has two outputs, use `[result, ~] = loadOrRun(@f, {}, ...)` so that `loadOrRun` knows to cache the second output as well for future use. 
* LORDAP will create files in your project (unless you configure outputs to be elsewhere). With the default options, you will want to add `.cache/` and `.meta/` to your `.gitignore` file.
* Unix filenames are limited to 255 characters. LORDAP will automatically and transparently "hash" filenames longer than this. Warnings will be issued when there are hash collisions. However, hashed files cannot be easily searched in your filesystem (they will look something like `84D2F807.mat`), and should be avoided. Tips for reducing filename sizes:
    * use short function names
    * use short query field names
* Be careful making changes to options.defaultQuery, as this may result in a mismatch between previously cached filenames and new results.
* LORDAP does not scale well, especially to complex "queries." [DataJoint](https://datajoint.io) is a better option in this situation, since it leverages the speed and scalability of a SQL database backend.
* Behavior of "onDependencyChange"
    * LORDAP uses modification timestamps on a `.m` file to detect when the associated data has become stale and should be deleted.
    * There are essentially two modes: ignore the problem completely or aggressively delete cached files (which may unnecessarily force other things to be recomputed later).
    * Avoid wrapping _local_ functions in `loadOrRun`, since any change to the file will trigger the deletion of cached results. Instead, each cached function should be given its own file.
    * Does not work for anonymous functions or packages like `+foo/bar.m` (which would be referenced as `@foo.bar`).

License
---

[GNU GPLv3](LICENSE.txt)

Note that this license must be copied and referenced wherever this project is used.

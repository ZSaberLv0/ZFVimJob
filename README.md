
job util for `vim8` and `neovim`

features / why another remake:

* more convenient for caller and impl

    * fallback to `system()` if no job impl available

        * job callback invoke normally, no job send support, though

    * supply your own impl easily by setting `g:ZFVimJobImpl`

* many useful util functions

    * run multiple jobs or vim functions and manage them easily (`ZFGroupJobStart`)
    * manage job with task name, auto output to a temp log window (`ZFAsyncRun`)
    * abstract job output (`ZFJobOutput`)
        * output to `statusline` async (`ZFStatuslineLog`)
        * output to temp log window (`ZFLogWinAdd`)
    * observe file write event and run build script automatically (`ZFAutoScript`)


if you like my work, [check here](https://github.com/ZSaberLv0?utf8=%E2%9C%93&tab=repositories&q=ZFVim) for a list of my vim plugins


# How to use

1. use [Vundle](https://github.com/VundleVim/Vundle.vim) or any other plugin manager you like to install

    ```
    Plugin 'ZSaberLv0/ZFVimJob'
    Plugin 'ZSaberLv0/ZFVimPopup' " optional, support show job output as popup
    ```

1. start the job

    ```
    function! s:onOutput(jobStatus, text, type)
    endfunction
    function! s:onExit(jobStatus, exitCode)
    endfunction
    let jobId = ZFJobStart({
            \   'jobCmd' : 'your job cmd',
            \   'onOutput' : function('s:onOutput'),
            \   'onExit' : function('s:onExit'),
            \   'jobEncoding' : '',
            \   'jobTimeout' : 0,
            \ })
    ```

    `onExit` would be called when:

    * job finished successfully, exitCode would be `0`
    * job failed, exitCode would be the job's exitCode (ensured string type)
    * stopped manually by `ZFJobStop(jobId)`, exitCode would be `g:ZFJOBSTOP`

1. start multiple jobs

    ```
    function! s:group1_job1(jobStatus)
        " note you may chain vim functions by setting `jobCmd` to vim function
        " no async support for vim functions, though
        call doSomeHeavyWork()
    endfunction

    function! s:groupJobOnExit(groupJobStatus, exitCode)
    endfunction
    let groupJobId = ZFGroupJobStart({
            \   'jobList' : [
            \     [
            \       {'jobCmd' : 'group0_job0'},
            \       {'jobCmd' : 'group0_job1'},
            \       ...
            \     ],
            \     [
            \       {'jobCmd' : 'group1_job0'},
            \       {'jobCmd' : function('s:group1_job1')},
            \     ],
            \     ...
            \   ],
            \   'onExit' : function('s:groupJobOnExit'),
            \   'jobTimeout' : 0,
            \ })
    ```

    `group1_xxx` would start only after previous `group0_xxx`'s jobs
    all finished with `0` exitCode

    group's `onExit` would be called when:

    * all child job finished successfully, group job's exitCode would be `0`
    * any child failed with none `0` exitCode, group job's exitCode would be the child's exitCode
    * stopped manually by `ZFGroupJobStop(groupJobId)`, group job's exitCode would be `g:ZFJOBSTOP`

1. by default, we support `vim8`'s `job_start()` and `neovim`'s `jobstart()`,
    you may supply your own job impl by:

    ```
    function! s:jobStart(jobStatus, onOutput, onExit)
        let jobImplId = yourJobStart(...)
        " store impl data if necessary
        let a:jobStatus['jobImplData']['yourJobImplId'] = jobImplId
        " return 1 if success or 0 if failed
        return 1
    endfunction
    function! s:jobStop(jobStatus)
    endfunction
    function! s:jobSend(extraArgs0, extraArgs1, jobStatus, text)
    endfunction
    let g:ZFVimJobImpl = {
            \   'jobStart' : function('s:jobStart'),
            \   'jobStop' : function('s:jobStop'),
            \   'jobSend' : ZFJobFunc(function('s:jobSend'), [extraArgs0, extraArgs1]),
            \ }
    ```


# API

## Util functions

since low version vim doesn't support `function(func, argList)`,
we supply a wrapper to simulate:

* `ZFJobFunc(func[, argList])` : return a Dictionary that can be run by `ZFJobFuncCall(jobFunc, argList)`

    func can be:

    * vim `function('name')`
    * string or string list to `:execute`

        function params can be accessed by `a:000` series, example:

        ```
        let Fn = ZFJobFunc([
                \   'let ret = Wrap(a:1, a:2, a:3, a:4)',
                \   'let ZFJobFuncRet = ret["xxx"]',
                \ ], ['a', 'b'])
        call ZFJobFuncCall(Fn, ['c', 'd'])
        " Wrap() would be called as: Wrap('a', 'b', 'c', 'd')
        ```

        to return values within the strings to `:execute`, `let ZFJobFuncRet = yourValue`

* `ZFJobFuncCall(jobFunc, argList)` : run the function of `ZFJobFunc()`
* `ZFJobFuncInfo(jobFunc)` : return function info

and for timers:

* `ZFJobTimerStart(delay, ZFJobFunc(...))`
* `ZFJobTimerStop(timerId)`


# Jobs

* `ZFJobAvailable()`
* `ZFJobStart(jobCmd_or_jobOption)`

    jobOption:

    * `jobCmd` : your job cmd, or vim `func(jobStatus)`
    * `jobCwd` : cwd to run your job
    * `onLog` : `func(jobStatus, log)`
    * `onOutput` : `func(jobStatus, text, type[stdout/stderr])`
    * `onExit` : `func(jobStatus, exitCode)`
    * `jobLogEnable` : optional, when on, jobLog would be recorded, for debug use only
    * `jobEncoding` : optional, if supplied, encoding conversion would be made before passing output text
    * `jobTimeout` : optional, if supplied, ZFJobStop would be called with g:ZFJOBTIMEOUT
    * `jobFallback` : optional, true by default, whether fallback to `system()` if no job impl available,
    * `jobImplData` : {}, // optional, if supplied, merge to jobStatus['jobImplData']

* `ZFJobStop(jobId)`
* `ZFJobSend(jobId, text)`
* `ZFJobStatus(jobId)`

    ```
    {
      'jobId' : -1,
      'jobOption' : {},
      'jobOutput' : [],
      'jobLog' : [],
      'jobImplData' : {},
    }
    ```

* `ZFJobTaskMap()`
* `ZFJobInfo(jobStatus)`
* `ZFJobLog(jobId, log)`


# Group jobs

* `ZFGroupJobStart(groupJobOption)`

    ```
    groupJobOption: {
      'jobList' : [
        [
          {
            'jobCmd' : '',
            'onOutput' : '',
            'onExit' : '',
            ...
          },
          ...
        ],
        ...
      ],
      'jobCmd' : 'optional, used only when jobList not supplied',
      'jobCwd' : 'optional, if supplied, would use as default value for child ZFJobStart',
      'onLog' : 'optional, func(groupJobStatus, log)',
      'onOutput' : 'optional, func(groupJobStatus, text, type[stdout/stderr])',
      'onExit' : 'optional, func(groupJobStatus, exitCode)',
      'jobLogEnable' : 'optional, when on, jobLog would be recorded, for debug use only',
      'jobEncoding' : 'optional, if supplied, would use as default value for child ZFJobStart',
      'jobTimeout' : 'optional, if supplied, would use as default value for child ZFJobStart',
      'jobFallback' : 'optional, if supplied, would use as default value for child ZFJobStart',
      'jobImplData' : {}, // optional, if supplied, merge to groupJobStatus['jobImplData']

      'groupJobTimeout' : 'optional, if supplied, ZFGroupJobStop would be called with g:ZFJOBTIMEOUT',
      'onJobLog' : 'optional, func(groupJobStatus, jobStatus, log)',
      'onJobOutput' : 'optional, func(groupJobStatus, jobStatus, text, type[stdout/stderr])',
      'onJobExit' : 'optional, func(groupJobStatus, jobStatus, exitCode)',
    }
    ```

* `ZFGroupJobStop(groupJobId)`
* `ZFGroupJobSend(groupJobId, text)`
* `ZFGroupJobStatus(groupJobId)`

    ```
    groupJobStatus : {
      'jobId' : '',
      'jobOption' : {},
      'jobOutput' : [],
      'jobLog' : [],
      'jobStatusFailed' : {},
      'jobIndex' : 0,
      'jobStatusList' : [[{jobStatus}], [{jobStatus}, {jobStatus}]],
      'jobImplData' : {},
    }
    child jobStatus jobImplData: {
      'groupJobId' : '',
      'groupJobChildState' : '1: running, 0: successFinished, -1: failed',
      'groupJobChildIndex' : 0,
      'groupJobChildSubIndex' : 0,
    }
    ```

* `ZFGroupJobTaskMap()`
* `ZFGroupJobInfo(groupJobStatus)`
* `ZFGroupJobLog(groupJobId, log)`


# Utils

## Job output

* `call ZFJobOutput(jobStatus, text)`

    output accorrding to job's output configs:

    ```
    jobStatus : {
        'jobOption' : {
            'outputTo' : {
                'outputType' : 'statusline/logwin',
                'outputCallback' : 'function(jobStatus, text)',
                'outputId' : 'if exists, use this fixed outputId',
                'outputAutoCleanup' : 10000,
                'outputManualCleanup' : 3000,

                // extra config for actual impl
                'statusline' : {...},
                'logwin' : {
                    ...
                    'logwinNoCloseWhenFocused' : 1,
                    'logwinAutoClosePreferHide' : 0,
                },
            },
        },
    }
    ```

* `call ZFJobOutputCleanup(jobStatus)`

    manually cleanup output


### Statusline log

* `call ZFStatuslineLog('your msg'[, timeout])`

    output logs to statusline, restore statusline automatically if set by other code or timeout,
    or `call ZFStatuslineLogClear()` to restore manually


### Log window

* `call ZFLogWinAdd(logId, content)`

    output logs to a temp log window

* control the log window:

    * `call ZFLogWinShow(logId)`
    * `call ZFLogWinFocus(logId)`
    * `call ZFLogWinHide(logId)`
    * `call ZFLogWinClear(logId)`
    * `call ZFLogWinClose(logId)`

* `call ZFLogWinConfig(logId, option)`

    init or change log window config, the default option is:

    ```
    let g:ZFLogWin_defaultConfig = {
                \   'newWinCmd' : 'rightbelow 5new',
                \   'filetype' : 'ZFLogWin',
                \   'statusline' : '',
                \   'makeDefaultKeymap' : 1,
                \   'initCallback' : '',
                \   'cleanupCallback' : '',
                \   'updateCallback' : '',
                \   'lazyUpdate' : 100,
                \   'maxLine' : '10000',
                \   'revertLines' : 0,
                \   'autoShow' : 1,
                \ }
    ```

    * `statusline` : string or `function(logId)`
    * `makeDefaultKeymap` : if set, default `q` to hide log window
    * `initCallback` / `cleanupCallback` / `updateCallback` : `function(logId)`


## Async run

* `:ZFAsyncRun your cmd` or `call ZFAsyncRun(jobCmd_or_jobOption[, taskNameOrJobId])`

    run shell async, output accorrding to `ZFJobOutput`

    you may use `call ZFAsyncRunStop([taskNameOrJobId])` to cancel,
    or check full log by `:ZFAsyncRunLog`

options:

* `let g:ZFAsyncRun_outputTo = {...}`

    output log to where (see `ZFJobOutput`), default:

    ```
    let g:ZFAsyncRun_outputTo = {
                \   'outputType' : 'logwin',
                \   'outputInfo' : function('ZF_AsyncRunOutputInfo'),
                \   'logwin' : {
                \     'filetype' : 'ZFAsyncRunLog',
                \     'autoShow' : 1,
                \   },
                \   'popup' : {
                \     'pos' : 'bottom',
                \     'width' : 1.0/3,
                \     'height' : 1.0/4,
                \     'x' : 1,
                \     'y' : &cmdheight + 2,
                \     'wrap' : 1,
                \     'contentAlign' : 'bottom',
                \   },
                \ }
    ```


## Auto script

* `call ZFAutoScript(projDir, jobOption)`

    automaically run script when any file within `projDir` was written (via `FileWritePost` autocmd)

    `jobOption` can be `jobCmd` or:

    ```
    { // jobOption passed to ZFAsyncRun
        'autoScriptCallback' : 'optional, vim callback to execute, func(jobStatus, projDir, file)',
    }
    ```

    use `call ZFAutoScriptRemove([projDir])` to cancel,
    use `call ZFAutoScriptLog([projDir])` to get log,
    use `call ZFAutoScriptStatus([projDir])` for active config, which would return:

    ```
    {
        'projDir' : {}, // jobStatus
    }
    ```

    you may also use `let g:ZFAutoScript={'projDir' : jobOption}` to config before plugin load

    typical config:

    ```
    let g:ZFAutoScript = {
            \   '/YourProjPath' : {
            \     'jobCmd' : 'make',
            \     'jobCwd' : '/YourProjPath',
            \   },
            \ }
    ```

options:

* `let g:ZFAutoScript_outputTo = {...}`

    output log to where (see `ZFJobOutput`), default:

    ```
    let g:ZFAutoScript_outputTo = {
                \   'outputType' : 'popup',
                \   'outputId' : 'ZFAutoScript',
                \   'outputInfo' : function('ZF_AutoScriptOutputInfo'),
                \   'logwin' : {
                \     'newWinCmd' : '99wincmd l | vertical rightbelow 20new',
                \     'filetype' : 'ZFAutoScriptLog',
                \     'autoShow' : 1,
                \   },
                \   'popup' : {
                \     'pos' : 'right|bottom',
                \     'width' : 1.0/3,
                \     'height' : 1.0/4,
                \     'x' : 1,
                \     'y' : &cmdheight + 2,
                \     'wrap' : 0,
                \     'contentAlign' : 'bottom',
                \   },
                \ }
    ```



function! ZF_AutoScriptOutputInfo(jobStatus)
    let projDir = s:projDir(get(get(a:jobStatus, 'jobImplData', {}), 'ZFAutoScript_projDir', ''))
    return ZFJobRunningToken(a:jobStatus, ':') . 'ZFAutoScriptRun ' . fnamemodify(projDir, ':~')
endfunction

" ============================================================
if !exists('g:ZFAutoScript_outputTo')
    let g:ZFAutoScript_outputTo = {
                \   'outputType' : 'popup',
                \   'outputTypeSuccess' : 'popup',
                \   'outputTypeFail' : 'logwin',
                \   'outputId' : 'ZFAutoScript',
                \   'outputInfo' : function('ZF_AutoScriptOutputInfo'),
                \   'outputInfoInterval' : 1000,
                \   'logwin' : {
                \     'filetype' : 'ZFAutoScriptLog',
                \     'autoShow' : 1,
                \   },
                \   'popup' : {
                \     'pos' : 'right|bottom',
                \     'width' : 1.0/3,
                \     'height' : 1.0/4,
                \     'x' : 1,
                \     'y' : 2,
                \     'wrap' : 0,
                \     'contentAlign' : 'bottom',
                \   },
                \ }
endif

" ============================================================
command! -nargs=0 ZFAutoScriptToggle :call ZFAutoScriptToggle()
command! -nargs=* -complete=dir ZFAutoScriptRun :call ZFAutoScriptRun(<q-args>)
command! -nargs=0 ZFAutoScriptRunAll :call ZFAutoScriptRunAll()
command! -nargs=* -complete=dir ZFAutoScriptStop :call ZFAutoScriptStop(<q-args>)
command! -nargs=0 ZFAutoScriptStopAll :call ZFAutoScriptStopAll()
command! -nargs=* -complete=dir ZFAutoScriptLog :call ZFAutoScriptLog(<q-args>)
command! -nargs=0 ZFAutoScriptLogAll :call ZFAutoScriptLogAll()

" param: { // jobOption passed to ZFAsyncRun
"   'autoScriptDelay' : 'optional, delay before run, 200ms by default',
"   'autoScriptFilter' : 'optional, rules to filter file path, empty by default',
"       // can be one of these:
"       // * regexp string or list, pattern follow perl style if `othree/eregex.vim` installed
"       // * function(params), return 1 if filtered
"       //     params: {
"       //       'path' : 'the abs file path which was written',
"       //       'dir' : {}, // the formated rule dir passed from ZFAutoScript
"       //       'option' : {}, // the original jobOption passed from ZFAutoScript
"       //     }
"   'autoScriptBreakOnRun' : 'optional, whether break to prevent auto script in parent path to be run, 1 by default',
" }
function! ZFAutoScript(projDir, param)
    call ZFAutoScriptRemove(a:projDir)
    if empty(a:param)
        return 0
    endif

    let projDir = s:projDir(a:projDir)
    let paramType = type(a:param)
    if paramType == g:ZFJOB_T_STRING || paramType == g:ZFJOB_T_NUMBER || ZFJobFuncCallable(a:param)
        let jobOption = {
                    \   'jobCmd' : a:param,
                    \   'outputTo' : g:ZFAutoScript_outputTo,
                    \ }
    elseif paramType == g:ZFJOB_T_DICT
        let jobOption = deepcopy(a:param)
        let jobOption['outputTo'] = ZFJobOptionExtend(deepcopy(g:ZFAutoScript_outputTo), get(jobOption, 'outputTo', {}))
    else
        echomsg '[ZFVimJob] unsupported param type: ' . paramType
        return -1
    endif
    if !exists("jobOption['jobImplData']")
        let jobOption['jobImplData'] = {}
    endif
    let jobOption['jobImplData']['ZFAutoScript_projDir'] = projDir

    let s:config[projDir] = s:fixJobOption(jobOption)

    if len(s:config) == 1
        call s:start()
    endif
    return 1
endfunction

if !exists('s:ZFAutoScriptIsEnable')
    let s:ZFAutoScriptIsEnable = 1
endif
function! ZFAutoScriptEnable()
    let s:ZFAutoScriptIsEnable = 1
    echo '[ZFAutoScript] enabled'
endfunction
function! ZFAutoScriptDisable()
    let s:ZFAutoScriptIsEnable = 0
    echo '[ZFAutoScript] disabled'
endfunction
function! ZFAutoScriptIsEnable()
    return s:ZFAutoScriptIsEnable
endfunction
function! ZFAutoScriptToggle()
    if ZFAutoScriptIsEnable()
        call ZFAutoScriptDisable()
    else
        call ZFAutoScriptEnable()
    endif
endfunction

function! ZFAutoScriptRemove(...)
    let projDir = s:projDir(get(a:, 1, ''))
    if exists('s:config[projDir]')
        call s:runDelayStop(projDir)
        unlet s:config[projDir]
    endif
    if exists('s:status[projDir]')
        unlet s:status[projDir]
    endif
    call ZFAsyncRunStop(s:taskName(projDir))
    if empty(s:config)
        call s:stop()
    endif
endfunction

function! ZFAutoScriptRun(...)
    let projDir = s:projDir(get(a:, 1, ''))
    if empty(get(s:config, projDir, {}))
        return
    endif
    call s:run(projDir, get(a:, 2, ''))
endfunction

function! ZFAutoScriptRunAll()
    let projDirList = copy(keys(s:config))
    for projDir in projDirList
        call ZFAutoScriptRun(projDir)
    endfor
endfunction

function! ZFAutoScriptStop(...)
    let projDir = s:projDir(get(a:, 1, ''))
    call s:runDelayStop(projDir)
    call ZFAsyncRunStop(s:taskName(projDir))
endfunction

function! ZFAutoScriptStopAll()
    let projDirList = copy(keys(s:config))
    for projDir in projDirList
        call ZFAutoScriptStop(projDir)
    endfor
endfunction

function! ZFAutoScriptLog(...)
    let projDir = s:projDir(get(a:, 1, ''))
    let implStatus = ZFAsyncRunStatus(s:taskName(projDir))
    while empty(implStatus)
        let projDirPrev = projDir
        let projDir = fnamemodify(projDir, ':h')
        if projDir == projDirPrev
            break
        endif
        let implStatus = ZFAsyncRunStatus(s:taskName(projDir))
    endwhile
    return ZFAsyncRunLog(s:taskName(projDir))
endfunction

function! ZFAutoScriptLogAll()
    let ret = {}
    for projDir in keys(s:config)
        let ret[projDir] = ZFAsyncRunLog(s:taskName(projDir))
    endfor
    return ret
endfunction

function! ZFAutoScriptStatus(...)
    let projDir = s:projDir(get(a:, 1, ''))
    return get(s:status, projDir, {})
endfunction

function! ZFAutoScriptTaskMap()
    return s:status
endfunction

function! ZFAutoScriptConfig(...)
    let projDir = s:projDir(get(a:, 1, ''))
    return get(s:config, projDir, {})
endfunction

function! ZFAutoScriptConfigMap()
    return s:config
endfunction

" ============================================================
" {
"   'projDir' : {}, // original jobOption
" }
if !exists('s:config')
    let s:config = {}
endif
" {
"   'projDir' : {}, // jobStatus
" }
if !exists('s:status')
    let s:status = {}
endif

function! s:projDir(projDir)
    if empty(a:projDir)
        let projDir = getcwd()
    else
        let projDir = a:projDir
        " ^[ \t]*"(.*)"[ \t]*$
        let projDir = substitute(projDir, '^[ \t]*"\(.*\)"[ \t]*$', '\1', 'g')
    endif
    return substitute(CygpathFix_absPath(projDir), '\/\+$', '', 'g')
endfunction

function! s:taskName(projDir)
    return 'ZFAutoScript:' . a:projDir
endfunction

function! s:start()
    augroup ZFAutoScript_augroup
        autocmd!
        autocmd BufWritePost * call s:fileWrite()
    augroup END
endfunction

function! s:stop()
endfunction

function! s:fileWrite()
    if !s:ZFAutoScriptIsEnable
        return
    endif
    let file = expand('<afile>:p')
    if empty(file)
        return
    endif
    let file = s:projDir(file)

    let projDirToRun = []
    for projDir in keys(s:config)
        if strpart(file, 0, len(projDir)) != projDir
                    \ || (len(file) > len(projDir) && file[len(projDir)] != '/')
            continue
        endif
        if s:autoScriptFilterCheck(projDir, file)
            continue
        endif
        call add(projDirToRun, projDir)
    endfor
    call sort(projDirToRun)

    let i = len(projDirToRun) - 1
    while i >= 0
        let projDir = projDirToRun[i]
        let jobOption = s:config[projDir]
        call ZFAutoScriptStop(projDir)
        let autoScriptBreakOnRun = get(jobOption, 'autoScriptBreakOnRun', 1)
        let autoScriptDelay = get(jobOption, 'autoScriptDelay', 200)
        if autoScriptDelay > 0
            let jobOption['autoScriptDelayTimerId'] = ZFJobTimerStart(
                        \ autoScriptDelay,
                        \ ZFJobFunc('ZFAutoScriptImpl_runDelay', [projDir, file]))
        else
            call s:run(projDir, file)
        endif

        if autoScriptBreakOnRun
            break
        endif

        let i -= 1
    endwhile
endfunction

function! s:autoScriptFilterCheck(projDir, file)
    let jobOption = s:config[a:projDir]
    let Fn_autoScriptFilter = get(jobOption, 'autoScriptFilter', '')
    if empty(Fn_autoScriptFilter)
        return 0
    endif
    if type(Fn_autoScriptFilter) == g:ZFJOB_T_LIST
        let autoScriptFilterList = Fn_autoScriptFilter
    else
        let autoScriptFilterList = [Fn_autoScriptFilter]
    endif

    for Fn in autoScriptFilterList
        if type(Fn) == g:ZFJOB_T_STRING
            if exists('*E2v')
                let pattern = E2v(Fn)
            else
                let pattern = Fn
            endif
            if match(a:file, pattern) >= 0
                return 1
            endif
        elseif ZFJobFuncCallable(Fn)
            if ZFJobFuncCall(Fn, {
                        \   'path' : a:file,
                        \   'dir' : a:projDir,
                        \   'option' : jobOption,
                        \ })
                return 1
            endif
        endif
    endfor
    return 0
endfunction

function! s:runDelayStop(projDir)
    let jobOption = get(s:config, a:projDir, {})
    if empty(jobOption)
        return
    endif
    if get(jobOption, 'autoScriptDelayTimerId', -1) != -1
        call ZFJobTimerStop(jobOption['autoScriptDelayTimerId'])
        let jobOption['autoScriptDelayTimerId'] = -1
    endif
endfunction
function! ZFAutoScriptImpl_runDelay(projDir, file, ...)
    let jobOption = get(s:config, a:projDir, {})
    if empty(jobOption)
        return
    endif
    let jobOption['autoScriptDelayTimerId'] = -1
    call s:run(a:projDir, a:file)
endfunction
function! s:run(projDir, file)
    call s:runDelayStop(a:projDir)
    let jobId = ZFAsyncRun(s:config[a:projDir], s:taskName(a:projDir))
    if jobId != -1
        let s:status[a:projDir] = ZFGroupJobStatus(jobId)
    endif
endfunction

" ============================================================
function! s:fixJobOption(jobOption)
    let a:jobOption['onEnter'] = ZFJobFunc('ZFAutoScriptImpl_onEnter', [get(a:jobOption, 'onEnter', '')])
    let a:jobOption['onExit'] = ZFJobFunc('ZFAutoScriptImpl_onExit', [get(a:jobOption, 'onExit', '')])
    return a:jobOption
endfunction

function! ZFAutoScriptImpl_onEnter(onEnter, jobStatus)
    if get(a:jobStatus['jobOption'], 'appendJobEnterInfo', get(g:, 'ZFAutoScript_appendJobEnterInfo', 1))
        call s:appendJobInfo(a:jobStatus, printf('JOB ENTER : %s', ZFGroupJobInfo(a:jobStatus)))
        call s:appendJobInfo(a:jobStatus, '============================================================')
    endif
    call ZFJobFuncCall(a:onEnter, [a:jobStatus])
endfunction
function! ZFAutoScriptImpl_onExit(onExit, jobStatus, exitCode)
    if get(a:jobStatus['jobOption'], 'appendJobExitInfo', get(g:, 'ZFAutoScript_appendJobExitInfo', 1))
        call s:appendJobInfo(a:jobStatus, '------------------------------------------------------------')
        call s:appendJobInfo(a:jobStatus, printf('JOB EXIT : %s : %s', a:exitCode, ZFGroupJobInfo(a:jobStatus)))
    endif
    call ZFJobFuncCall(a:onExit, [a:jobStatus, a:exitCode])
endfunction
function! s:appendJobInfo(jobStatus, text)
    call ZFGroupJobLog(a:jobStatus, a:text)
    call add(a:jobStatus['jobOutput'], a:text)
    call ZFJobOutput(a:jobStatus, a:text)
endfunction

" ============================================================
function! ZFAutoScriptConfigReload()
    for projDir in keys(s:config)
        call ZFAutoScriptRemove(projDir)
    endfor

    if exists('g:ZFAutoScript')
        for projDir in keys(g:ZFAutoScript)
            call ZFAutoScript(projDir, g:ZFAutoScript[projDir])
        endfor
    endif
endfunction

call ZFAutoScriptConfigReload()


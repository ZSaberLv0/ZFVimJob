
function! ZF_AutoScriptStatusline(logId)
    let jobStatus = ZFLogWinJobStatusGet(a:logId)
    if len(get(jobStatus, 'exitCode', '')) == 0
        let statusline = ' (running) '
    else
        let statusline = '(finished) '
    endif
    let projDir = s:projDir(get(get(jobStatus, 'jobImplData', {}), 'ZFAutoScript_projDir', ''))
    return ZFStatuslineLogValue(statusline . fnamemodify(projDir, ':~'))
endfunction

" ============================================================
if !exists('g:ZFAutoScript_outputTo')
    let g:ZFAutoScript_outputTo = {
                \   'outputType' : 'popup',
                \   'outputTaskId' : 'ZFAutoScript',
                \   'logwin' : {
                \     'newWinCmd' : '99wincmd l | vertical rightbelow 20new',
                \     'filetype' : 'ZFAutoScriptLog',
                \     'statusline' : function('ZF_AutoScriptStatusline'),
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
"   'autoScriptCallback' : 'optional, vim callback to execute, func(jobStatus, projDir, file)',
"   'autoScriptDelay' : 'optional, delay before run, 1 second by default',
"   'autoScriptDelayTimerId' : 'internal use, the timer id',
" }
function! ZFAutoScript(projDir, param)
    let projDir = s:projDir(a:projDir)
    let outputConfig = {
                \   'outputTo' : g:ZFAutoScript_outputTo,
                \ }
    if type(a:param) == type('') || ZFJobFuncCallable(a:param)
        let jobOption = extend(outputConfig, {
                    \   'jobCmd' : a:param,
                    \ })
    elseif type(a:param) == type({})
        let jobOption = extend(outputConfig, a:param)
    else
        echo '[ZFVimJob] unsupported param type: ' . type(a:param)
        return -1
    endif
    let jobOption['outputTo'] = deepcopy(jobOption['outputTo'])

    if !exists("jobOption['jobImplData']")
        let jobOption['jobImplData'] = {}
    endif
    let jobOption['jobImplData']['ZFAutoScript_projDir'] = projDir

    let s:config[projDir] = jobOption
    call ZFAsyncRunStop(s:taskName(projDir))

    if len(s:config) == 1
        call s:start()
    endif
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
    call ZFAsyncRunLog(s:taskName(projDir))
endfunction

function! ZFAutoScriptLogAll()
    let ret = {}
    for projDir in keys(s:config)
        let ret[projDir] = ZFAutoScriptLog(projDir)
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
        return fnamemodify(getcwd(), ':p')
    else
        return fnamemodify(a:projDir, ':p')
    endif
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
    for projDir in keys(s:config)
        if strpart(file, 0, len(projDir)) != projDir
            continue
        endif
        let jobOption = s:config[projDir]
        call ZFAutoScriptStop(projDir)
        if get(jobOption, 'autoScriptDelay', 1) > 0
            let jobOption['autoScriptDelayTimerId'] = ZFJobTimerStart(
                        \ get(jobOption, 'autoScriptDelay', 1),
                        \ ZFJobFunc(function('s:runDelay'), [projDir, file]))
        else
            call s:run(projDir, file)
        endif
        break
    endfor
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
function! s:runDelay(projDir, file, ...)
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
    call ZFJobFuncCall(get(s:config[a:projDir], 'autoScriptCallback', ''), [s:status[a:projDir], a:projDir, a:file])
endfunction

" ============================================================
if exists('g:ZFAutoScript')
    for projDir in keys(g:ZFAutoScript)
        call ZFAutoScript(projDir, g:ZFAutoScript[projDir])
    endfor
endif


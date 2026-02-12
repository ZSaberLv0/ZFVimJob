
let g:ZFJOBSTOP = 'ZFJOBSTOP'
let g:ZFJOBERROR = 'ZFJOBERROR'
let g:ZFJOBTIMEOUT = 'ZFJOBTIMEOUT'

let g:ZFJOB_T_NUMBER = type(0)
let g:ZFJOB_T_STRING = type('')
let g:ZFJOB_T_LIST = type([])
let g:ZFJOB_T_DICT = type({})
let g:ZFJOB_T_FUNC = type(function('function'))

if !exists('g:ZFJobVerboseLog')
    let g:ZFJobVerboseLog = []
endif
if !exists('g:ZFJobVerboseLogEnable')
    let g:ZFJobVerboseLogEnable = 0
endif

" use timer to delay to invoke onOutput callback for job
" mainly for https://github.com/vim/vim/issues/1320
" can also be used to achieve buffered output for performance
if !exists('g:ZFJobOutputDelay')
    let g:ZFJobOutputDelay = 5
endif

if !exists('g:ZFJobOutputLimit')
    let g:ZFJobOutputLimit = 2000
endif

if !exists('g:ZFJobOutputCRFix')
    let g:ZFJobOutputCRFix = 1
endif

" ============================================================
function! ZFJobAvailable()
    " g:ZFJobImpl : {
    "   'jobStart' : 'func(jobStatus, onOutput(textList, type[stdout/stderr]), onExit(exitCode)), return 0/1',
    "   'jobStop' : 'func(jobStatus), return 0/1',
    "   'jobSend' : 'optional, func(jobStatus, text), return 0/1',
    " }
    return !empty(get(get(g:, 'ZFJobImpl', {}), 'jobStart', {}))
endfunction

" param can be jobCmd or jobOption: {
" 'jobCmd' : 'job cmd',
"            // jobCmd can be:
"            // * string, shell command to run as job
"            // * vim `function(jobStatus)` or any callable object to `ZFJobFuncCall()`, return:
"            //   * `{output:xxx, exitCode:0}` to indicate invoke result, if none, it's considered as success
"            //   * `{notifySend(jobStatus, text), notifyStop:function(jobStatus, exitCode), }` to indicate job is running in fake async mode,
"            //     the `notifySend` would be called if owner `ZFJobSend()` called,
"            //     the `notifyStop` would be called if owner `ZFJobStop()` called,
"            //     also, you must call these method to implement job logic
"            //     * `ZFJobFallback_notifyOutput(jobStatus, textList, type[stdout/stderr])`
"            //     * `ZFJobFallback_notifyExit(jobStatus, exitCode)`
"            // * number, use `ZFJobTimerStart()` to delay,
"            //   has better performance than starting a `sleep` job
"            // * empty or not exist, a dummy job, but onEnter/onExit would be called normally
"   'jobCwd' : 'optional, cwd to run the job',
"   'jobEnv' : 'optional, a dictionary to specify the environement variable',
"   'onLog' : 'optional, func(jobStatus, log)',
"   'onOutputFilter' : 'optional, func(jobStatus, textList, type[stdout/stderr]), modify textList or empty to discard',
"   'onOutput' : 'optional, func(jobStatus, textList, type[stdout/stderr])',
"   'onEnter' : 'optional, func(jobStatus), note: jobId not available during onEnter',
"   'onExit' : 'optional, func(jobStatus, exitCode)',
"   'jobOutputDelay' : 'optional, default is g:ZFJobOutputDelay',
"   'jobOutputLimit' : 'optional, max line of jobOutput that would be stored in jobStatus, default is g:ZFJobOutputLimit',
"   'jobOutputCRFix' : 'optional, whether try to replace `\r\n` to `\n`, default is g:ZFJobOutputCRFix',
"   'jobEncoding' : 'optional, if supplied, encoding conversion would be made before passing output textList',
"   'jobTimeout' : 'optional, if supplied and timeout, ZFJobStop would be called with g:ZFJOBTIMEOUT (or 0 if jobTimeout < 0)',
"   'jobFallback' : 'optional, true by default, whether fallback to `system()` if no job impl available',
"   'jobImplData' : {}, // optional, if supplied, merge to jobStatus['jobImplData']
" }
" return:
" * -1 if failed
" * 0 if fallback to `system()`
" * jobId if success (ensured greater than 0)
function! ZFJobStart(param)
    return s:jobStart(a:param)
endfunction

" return 0/1 : whether stop success
function! ZFJobStop(jobId, ...)
    return s:jobStop(ZFJobStatus(a:jobId), '' . get(a:, 1, g:ZFJOBSTOP), 1)
endfunction

" return 0/1 : whether send success
function! ZFJobSend(jobId, text)
    return s:jobSend(a:jobId, a:text)
endfunction

" return: {
"   'jobId' : -1,
"   'startTime' : localtime(),
"   'jobOption' : {},
"   'jobOutput' : [],
"   'exitCode' : 'ensured string type, empty if running, not empty when job finished',
"   'jobImplData' : {},
" }
function! ZFJobStatus(jobId)
    return get(s:jobMap, a:jobId, {})
endfunction

" return: {jobId : jobStatus}
function! ZFJobTaskMap()
    return s:jobMap
endfunction
function! ZFJobTaskMapInfo()
    let ret = []
    for jobStatus in values(s:jobMap)
        let info = ZFJobInfo(jobStatus)
        call add(ret, info)
        echo info
    endfor
    return ret
endfunction

function! ZFJobInfo(jobStatus)
    let T_jobCmd = get(get(a:jobStatus, 'jobOption', {}), 'jobCmd', '')
    if type(T_jobCmd) == g:ZFJOB_T_NUMBER
        return 'sleep ' . T_jobCmd . 'ms'
    else
        return ZFJobFuncInfo(T_jobCmd)
    endif
endfunction

function! ZFJobLog(jobIdOrJobStatus, log)
    if type(a:jobIdOrJobStatus) == g:ZFJOB_T_DICT
        let jobStatus = a:jobIdOrJobStatus
    else
        let jobStatus = ZFJobStatus(a:jobIdOrJobStatus)
    endif
    if !empty(jobStatus)
        call s:jobLog(jobStatus, a:log)
    endif
endfunction

" ============================================================
if !exists('s:jobIdCur')
    let s:jobIdCur = 0
endif
if !exists('s:jobMap')
    let s:jobMap = {}
endif

function! s:jobIdNext()
    while 1
        let s:jobIdCur += 1
        if s:jobIdCur <= 0
            let s:jobIdCur = 1
        endif
        if exists('s:jobMap[s:jobIdCur]')
            continue
        endif
        return s:jobIdCur
    endwhile
endfunction

if exists('*strftime')
    function! s:jobLogFormat(jobStatus, log)
        return strftime('%H:%M:%S') . ' job ' . a:jobStatus['jobId'] . ' ' . a:log
    endfunction
else
    function! s:jobLogFormat(jobStatus, log)
        return 'job ' . a:jobStatus['jobId'] . ' ' . a:log
    endfunction
endif
function! s:jobLog(jobStatus, log)
    let Fn_onLog = get(a:jobStatus['jobOption'], 'onLog', '')
    if g:ZFJobVerboseLogEnable || !empty(Fn_onLog)
        let log = s:jobLogFormat(a:jobStatus, a:log)
        if g:ZFJobVerboseLogEnable
            call add(g:ZFJobVerboseLog, log)
        endif
        call ZFJobFuncCall(Fn_onLog, [a:jobStatus, log])
    endif
endfunction

function! s:jobRemove(jobId)
    if exists('s:jobMap[a:jobId]')
        return remove(s:jobMap, a:jobId)
    else
        return {}
    endif
endfunction

augroup ZFVimJob_ZFJobOptionSetup_augroup
    autocmd!
    autocmd User ZFJobOptionSetup silent
augroup END
function! s:jobStart(param)
    let paramType = type(a:param)
    if paramType == g:ZFJOB_T_STRING || paramType == g:ZFJOB_T_NUMBER || ZFJobFuncCallable(a:param)
        let jobOption = {
                    \   'jobCmd' : a:param,
                    \ }
    elseif paramType == g:ZFJOB_T_DICT
        let jobOption = copy(a:param)
    else
        echomsg '[ZFVimJob] unsupported param type: ' . paramType
        return -1
    endif

    let g:ZFJobOptionSetup = jobOption
    doautocmd User ZFJobOptionSetup
    unlet g:ZFJobOptionSetup

    let jobStatus = {
                \   'jobId' : -1,
                \   'startTime' : localtime(),
                \   'jobOption' : jobOption,
                \   'jobOutput' : [],
                \   'exitCode' : '',
                \   'jobImplData' : copy(get(jobOption, 'jobImplData', {})),
                \ }
    call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])

    if type(get(jobOption, 'jobCmd', '')) == g:ZFJOB_T_NUMBER
        return s:sleepJob_jobStart(jobStatus)
    endif

    if !ZFJobAvailable()
        redraw!
        if get(jobOption, 'jobFallback', 1)
            return s:fallbackJob_jobStart(jobStatus)
        endif
        echomsg '[ZFVimJob] no job impl available'
        return -1
    endif

    if empty(get(jobOption, 'jobCmd', ''))
        let jobStatus['exitCode'] = '0'
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onExit', ''), [jobStatus, '0'])
        return 0
    endif

    if type(jobOption['jobCmd']) != g:ZFJOB_T_STRING && ZFJobFuncCallable(jobOption['jobCmd'])
        return s:fallbackJob_jobStart(jobStatus)
    endif

    let success = ZFJobFuncCall(g:ZFJobImpl['jobStart'], [
                \   jobStatus
                \ , ZFJobFunc('ZFJobImpl_onOutput', [jobStatus])
                \ , ZFJobFunc('ZFJobImpl_onExit', [jobStatus])
                \ ])
    if !success
        redraw!
        call s:jobLog(jobStatus, 'unable to start job: `' . ZFJobInfo(jobStatus) . '`')
        echomsg '[ZFVimJob] unable to start job: ' . ZFJobInfo(jobStatus)
        let jobStatus['exitCode'] = g:ZFJOBERROR
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onExit', ''), [jobStatus, g:ZFJOBERROR])
        return -1
    endif

    if get(jobOption, 'jobTimeout', 0) != 0 && ZFJobTimerAvailable()
        let jobStatus['jobImplData']['jobTimeoutId'] = ZFJobTimerStart(abs(jobOption['jobTimeout']), ZFJobFunc('ZFJobImpl_onTimeout', [jobStatus, jobOption['jobTimeout']]))
    endif

    let jobId = s:jobIdNext()
    let jobStatus['jobId'] = jobId
    call s:jobLog(jobStatus, 'start: `' . ZFJobInfo(jobStatus) . '`')
    let s:jobMap[jobId] = jobStatus
    return jobId
endfunction

function! s:jobStop(jobStatus, exitCode, callImpl)
    if empty(a:jobStatus)
        return 0
    endif
    let a:jobStatus['exitCode'] = a:exitCode

    if get(a:jobStatus['jobImplData'], 'jobOutputDelayTaskId', -1) >= 0
        call ZFJobTimerStop(a:jobStatus['jobImplData']['jobOutputDelayTaskId'])
        unlet a:jobStatus['jobImplData']['jobOutputDelayTaskId']
        call s:onOutputAction(a:jobStatus, a:jobStatus['jobImplData']['jobOutputDelayTextList'], a:jobStatus['jobImplData']['jobOutputDelayType'])
        if exists("a:jobStatus['jobImplData']['jobOutputDelayExitCode']")
            unlet a:jobStatus['jobImplData']['jobOutputDelayExitCode']
        endif
    endif
    let jobTimeoutId = get(a:jobStatus['jobImplData'], 'jobTimeoutId', -1)
    if jobTimeoutId != -1
        call ZFJobTimerStop(jobTimeoutId)
        unlet a:jobStatus['jobImplData']['jobTimeoutId']
    endif

    call s:jobLog(a:jobStatus, 'stop with exitCode ' . a:exitCode . ': `' . ZFJobInfo(a:jobStatus) . '`')

    if a:jobStatus['jobId'] > 0
        let jobStatus = s:jobRemove(a:jobStatus['jobId'])
        if empty(jobStatus)
            return 0
        endif
    endif

    if exists("a:jobStatus['jobImplData']['sleepJob']")
        let ret = s:sleepJob_jobStop(a:jobStatus, a:exitCode)
    elseif exists("a:jobStatus['jobImplData']['fallbackJob_fakeAsync']")
        let ret = s:fallbackJob_jobStop(a:jobStatus, a:exitCode)
    else
        if a:callImpl
            let ret = ZFJobFuncCall(g:ZFJobImpl['jobStop'], [a:jobStatus])
        else
            let ret = 1
        endif
    endif

    call ZFJobFuncCall(get(a:jobStatus['jobOption'], 'onExit', ''), [a:jobStatus, a:exitCode])
    call ZFJobOutputCleanup(a:jobStatus)

    if a:exitCode != a:jobStatus['exitCode']
        call s:jobLog(a:jobStatus, 'exitCode changed during onExit: ' . a:exitCode . ' => ' . a:jobStatus['exitCode'])
    endif

    let a:jobStatus['jobId'] = -1
    return ret
endfunction

function! ZFJobImplSrcEncoding(jobStatus)
    if !exists('*iconv')
        return ''
    endif
    let ret = get(a:jobStatus['jobOption'], 'jobEncoding', '')
    if ret == &encoding
        return ''
    else
        return ret
    endif
endfunction

function! s:jobSend(jobId, text)
    let jobStatus = ZFJobStatus(a:jobId)
    if empty(jobStatus)
        return 0
    endif

    call s:jobLog(jobStatus, 'send: ' . substitute(substitute(a:text, '\n', '\\n', 'g'), '\r', '\\r', 'g'))
    let jobEncoding = ZFJobImplSrcEncoding(jobStatus)
    if empty(jobEncoding)
        let text = a:text
    else
        let text = iconv(a:text, &encoding, jobEncoding)
    endif

    if exists("a:jobStatus['jobImplData']['sleepJob']")
        return 0
    elseif exists("a:jobStatus['jobImplData']['fallbackJob_fakeAsync']")
        return s:fallbackJob_jobSend(a:jobStatus, text)
    else
        let Fn_jobSend = get(g:ZFJobImpl, 'jobSend', '')
        if empty(Fn_jobSend)
            return 0
        endif
        return ZFJobFuncCall(Fn_jobSend, [jobStatus, text])
    endif
endfunction

function! ZFJobImpl_onOutput(jobStatus, textList, type)
    let jobEncoding = ZFJobImplSrcEncoding(a:jobStatus)

    let textListLen = len(a:textList)
    let iTextList = 0
    while iTextList < textListLen
        if get(g:, 'ZFVimJobFixTermSpecialChar', 1)
            let a:textList[iTextList] = substitute(a:textList[iTextList], "\x1b\[[0-9;]*[a-zA-Z]", '', 'g')
            let a:textList[iTextList] = substitute(a:textList[iTextList], "\x18", '', 'g')
        endif

        if !empty(jobEncoding)
            let a:textList[iTextList] = iconv(a:textList[iTextList], jobEncoding, &encoding)
        endif

        if get(g:, 'ZFVimJobFixTermCR', 1) && (has('win32') || has('win64'))
            let a:textList[iTextList] = substitute(a:textList[iTextList], "\x0d", '', 'g')
        endif

        let iTextList += 1
    endwhile

    if !empty(get(a:jobStatus['jobOption'], 'onOutputFilter', ''))
        call ZFJobFuncCall(a:jobStatus['jobOption']['onOutputFilter'], [a:jobStatus, a:textList, a:type])
        if empty(a:textList)
            return
        endif
    endif

    if ZFJobTimerAvailable() && get(a:jobStatus['jobOption'], 'jobOutputDelay', g:ZFJobOutputDelay) >= 0
        let needDelay = 0
        if get(a:jobStatus['jobImplData'], 'jobOutputDelayTaskId', -1) >= 0
            if a:jobStatus['jobImplData']['jobOutputDelayType'] == a:type
                call extend(a:jobStatus['jobImplData']['jobOutputDelayTextList'], a:textList)
            else
                call s:onOutputAction(a:jobStatus, a:jobStatus['jobImplData']['jobOutputDelayTextList'], a:jobStatus['jobImplData']['jobOutputDelayType'])
                let needDelay = 1
            endif
        else
            let needDelay = 1
        endif
        if needDelay
            let a:jobStatus['jobImplData']['jobOutputDelayTextList'] = a:textList
            let a:jobStatus['jobImplData']['jobOutputDelayType'] = a:type
            let a:jobStatus['jobImplData']['jobOutputDelayTaskId'] = ZFJobTimerStart(
                        \   get(a:jobStatus['jobImplData'], 'jobOutputDelay', g:ZFJobOutputDelay),
                        \   ZFJobFunc('ZFJobImpl_onOutputDelayCallback', [a:jobStatus])
                        \ )
        endif
    else
        call s:onOutputAction(a:jobStatus, a:textList, a:type)
    endif
endfunction
" jobImplData : {
"   'jobOutputDelayTaskId' : '', // only exist when delaying
"   'jobOutputDelayTextList' : '',
"   'jobOutputDelayType' : '',
"   'jobOutputDelayExitCode' : exitCode, // only exist when onExit during delaying
" }
function! ZFJobImpl_onOutputDelayCallback(jobStatus, ...)
    if get(a:jobStatus['jobImplData'], 'jobOutputDelayTaskId', -1) == -1
        return
    endif
    unlet a:jobStatus['jobImplData']['jobOutputDelayTaskId']
    call s:onOutputAction(a:jobStatus, a:jobStatus['jobImplData']['jobOutputDelayTextList'], a:jobStatus['jobImplData']['jobOutputDelayType'])

    if exists("a:jobStatus['jobImplData']['jobOutputDelayExitCode']")
        let exitCode = a:jobStatus['jobImplData']['jobOutputDelayExitCode']
        unlet a:jobStatus['jobImplData']['jobOutputDelayExitCode']
        call s:jobStop(a:jobStatus, exitCode, 0)
    endif
endfunction
function! s:onOutputAction(jobStatus, textList, type)
    if get(a:jobStatus['jobOption'], 'jobOutputCRFix', g:ZFJobOutputCRFix)
        let i = len(a:textList) - 1
        while i >= 0
            let a:textList[i] = substitute(a:textList[i], '\r', '', 'g')
            let i -= 1
        endwhile
    endif

    for text in a:textList
        call s:jobLog(a:jobStatus, 'output [' . a:type . ']: ' . text)
    endfor
    call extend(a:jobStatus['jobOutput'], a:textList)
    let jobOutputLimit = get(a:jobStatus['jobOption'], 'jobOutputLimit', g:ZFJobOutputLimit)
    if jobOutputLimit >= 0 && len(a:jobStatus['jobOutput']) > jobOutputLimit
        call remove(a:jobStatus['jobOutput'], 0, len(a:jobStatus['jobOutput']) - jobOutputLimit - 1)
    endif

    call ZFJobFuncCall(get(a:jobStatus['jobOption'], 'onOutput', ''), [a:jobStatus, a:textList, a:type])
    call ZFJobOutput(a:jobStatus, a:textList, a:type)
endfunction

function! ZFJobImpl_onExit(jobStatus, exitCode)
    if get(a:jobStatus['jobImplData'], 'jobOutputDelayTaskId', -1) == -1
        call s:jobStop(a:jobStatus, a:exitCode, 0)
    else
        let a:jobStatus['jobImplData']['jobOutputDelayExitCode'] = a:exitCode
    endif
endfunction

function! ZFJobImpl_onTimeout(jobStatus, jobTimeout, ...)
    if exists("jobStatus['jobImplData']['jobTimeoutId']")
        unlet jobStatus['jobImplData']['jobTimeoutId']
    endif
    if a:jobTimeout < 0
        call ZFJobStop(a:jobStatus['jobId'], '0')
    else
        call ZFJobStop(a:jobStatus['jobId'], g:ZFJOBTIMEOUT)
    endif
endfunction

" ============================================================
function! ZFJobImplGetWindowsEncoding()
    if !exists('s:WindowsCodePage')
        let cp = system("@echo off && for /f \"tokens=2* delims=: \" %a in ('chcp') do (echo %a)")
        let cp = 'cp' . substitute(cp, '[\r\n]', '', 'g')
        let s:WindowsCodePage = cp
    endif
    return s:WindowsCodePage
endfunction

" update to envDesired, and return a dict for ZFJobImplEnvRestore
function! ZFJobImplEnvUpdate(envDesired)
    let envSaved = {}
    for key in keys(a:envDesired)
        execute printf('let envSaved[key] = $%s', key)
        execute printf('let $%s = a:envDesired[key]', key)
    endfor
    return envSaved
endfunction

" restore env set by ZFJobImplEnvUpdate
function! ZFJobImplEnvRestore(envSaved)
    for key in keys(a:envSaved)
        execute printf('let $%s = a:envSaved[key]', key)
    endfor
endfunction

" escape cmd accorrding to envDesired
" modes: {
"    'Windows' : 1/0/-1, // -1 by default
"    'Posix' : 1/0/-1, // 1 by default
" }
"
" for Windows:
"   %VAR% : escaped
"   \%VAR\% : not escaped
"
" for Posix:
"   $VAR : escaped
"   ${VAR} : escaped
"   \$VAR : not escaped
"   \${VAR} : not escaped
function! ZFJobImplEnvEscapeCmd(cmd, envDesired, ...)
    if empty(a:cmd)
        return a:cmd
    endif
    let cmd = a:cmd
    let token = nr2char(127)

    let modes = get(a:, 1, {})
    let modes_Windows = get(modes, 'Windows', -1)
    let modes_Posix = get(modes, 'Posix', 1)

    if (modes_Windows == -1 && ((has('win32') || has('win64')) && !has('unix')))
                \ || modes_Windows != 0
        let cmd = substitute(cmd, '\\%', token, 'g')
        while 1
            " %VAR%
            " (?<=%)[a-z_0-9]+(?=%)
            let var = matchstr(cmd, '\%(%\)\@<=[a-z_0-9]\+\%(%\)\@=')
            if !empty(var)
                let cmd = substitute(cmd, '%'.var.'%', s:envForVar(a:envDesired, var), 'g')
                continue
            endif

            break
        endwhile
        let cmd = substitute(cmd, token, '\\%', 'g')
    endif

    if (modes_Posix == -1 && has('unix'))
                \ || modes_Posix != 0
        let cmd = substitute(cmd, '\\\$', token, 'g')
        while 1
            " $VAR
            " (?<=\$)[a-z_0-9]+\>
            let var = matchstr(cmd, '\%(\$\)\@<=[a-z_0-9]\+\>')
            if !empty(var)
                let cmd = substitute(cmd, '\$'.var, s:envForVar(a:envDesired, var), 'g')
                continue
            endif

            " ${VAR}
            " (?<=\$\{)[a-z_0-9]+(?=\})
            let var = matchstr(cmd, '\%(\${\)\@<=[a-z_0-9]\+\%(}\)\@=')
            if !empty(var)
                let cmd = substitute(cmd, '\${'.var.'}', s:envForVar(a:envDesired, var), 'g')
                continue
            endif

            break
        endwhile
        let cmd = substitute(cmd, token, '\\\$', 'g')
    endif

    return cmd
endfunction
function! s:envForVar(envDesired, var)
    execute 'let def = $' . a:var
    let def = get(a:envDesired, a:var, def)
    return substitute(def, ' ', '\\\\ ', 'g')
endfunction

" ============================================================
" for sleep job, jobImplData: {
"   'sleepJob' : 'timerId', // ensured exists for sleepJob, reset to -1 when sleep done
" }
function! s:sleepJob_jobStart(jobStatus)
    let jobId = s:jobIdNext()
    let a:jobStatus['jobId'] = jobId
    call s:jobLog(a:jobStatus, 'start: `' . ZFJobInfo(a:jobStatus) . '`')
    let s:jobMap[jobId] = a:jobStatus
    let a:jobStatus['jobImplData']['sleepJob'] = ZFJobTimerStart(
                \ a:jobStatus['jobOption']['jobCmd'],
                \ ZFJobFunc('ZFJobImpl_sleepJob_jobStartDelay', [jobId]))
    return jobId
endfunction
function! ZFJobImpl_sleepJob_jobStartDelay(jobId, ...)
    let jobStatus = ZFJobStatus(a:jobId)
    if empty(jobStatus)
        return
    endif
    call s:jobStop(jobStatus, '0', 0)
endfunction
function! s:sleepJob_jobStop(jobStatus, exitCode)
    let sleepJobTimerId = a:jobStatus['jobImplData']['sleepJob']
    if sleepJobTimerId >= 0
        let a:jobStatus['jobImplData']['sleepJob'] = -1
        call ZFJobTimerStop(sleepJobTimerId)
        return 1
    else
        return 0
    endif
endfunction

" ============================================================
" for fallback job, jobImplData: {
"   'fallbackJob_fakeAsync' : { // ensured exists if in fake async mode
"     'notifySend' : function(jobStatus, text),
"     'notifyStop' : function(jobStatus, exitCode),
"   },
" }
function! s:fallbackJob_jobStart(jobStatus)
    let envSaved = ZFJobImplEnvUpdate(get(a:jobStatus['jobOption'], 'jobEnv', {}))
    let ret = s:fallbackJob_jobStartImpl(a:jobStatus)
    call ZFJobImplEnvRestore(envSaved)
    return ret
endfunction

function! s:fallbackJob_jobStartImpl(jobStatus)
    let jobId = s:jobIdNext()
    let a:jobStatus['jobId'] = jobId
    let s:jobMap[jobId] = a:jobStatus

    call s:jobLog(a:jobStatus, 'start (fallback): `' . ZFJobInfo(a:jobStatus) . '`')

    let T_jobCmd = get(a:jobStatus['jobOption'], 'jobCmd', '')
    if type(T_jobCmd) == g:ZFJOB_T_STRING
        let jobCmd = T_jobCmd
        if !empty(get(a:jobStatus['jobOption'], 'jobCwd', ''))
            let jobCmd = 'cd "' . a:jobStatus['jobOption']['jobCwd'] . '" && ' . jobCmd
        endif
        let result = system(jobCmd)
        let exitCode = '' . v:shell_error
    elseif type(T_jobCmd) == g:ZFJOB_T_NUMBER
        " for fallback, sleep job has nothing to do
        let result = ''
        let exitCode = '0'
    elseif ZFJobFuncCallable(T_jobCmd)
        if !empty(get(a:jobStatus['jobOption'], 'jobCwd', ''))
            let cwdSaved = CygpathFix_absPath(getcwd())
            let jobCwd = CygpathFix_absPath(a:jobStatus['jobOption']['jobCwd'])
            if cwdSaved != jobCwd
                execute 'cd ' . fnameescape(jobCwd)
            else
                let cwdSaved = ''
            endif
        else
            let cwdSaved = ''
        endif

        let result = ''
        let exitCode = '0'
        if exists('*execute')
            try
                let result = execute('let T_result = ZFJobFuncCall(T_jobCmd, [a:jobStatus])', 'silent')
            catch
                let result = v:exception
                let exitCode = '-1'
            endtry
        else
            try
                redir => result
                silent let T_result = ZFJobFuncCall(T_jobCmd, [a:jobStatus])
            catch
                let result = v:exception
            finally
                redir END
            endtry
        endif

        if !empty(cwdSaved)
            execute 'cd ' . fnameescape(cwdSaved)
        endif

        if exists('T_result') && type(T_result) == g:ZFJOB_T_DICT
            if exists("T_result['notifyStop']")
                let a:jobStatus['jobImplData']['fallbackJob_fakeAsync'] = T_result
                return jobId
            elseif exists("T_result['output']") && exists("T_result['exitCode']")
                let result = T_result['output']
                let exitCode = '' . T_result['exitCode']
            endif
        endif
    else
        call s:jobLog(a:jobStatus, 'invalid jobCmd')
        call s:jobRemove(a:jobStatus['jobId'])
        echomsg '[ZFVimJob] invalid jobCmd'
        call ZFJobFuncCall(get(a:jobStatus['jobOption'], 'onExit', ''), [a:jobStatus, g:ZFJOBERROR])
        return -1
    endif

    let jobEncoding = ZFJobImplSrcEncoding(a:jobStatus)
    if empty(jobEncoding)
        let jobOutput = result
    else
        let jobOutput = iconv(result, jobEncoding, &encoding)
    endif
    call ZFJobImpl_onOutput(a:jobStatus, split(jobOutput, "\n"), 'stdout')

    call ZFJobImpl_onExit(a:jobStatus, exitCode)
    return 0
endfunction

" only called when jobImplData.fallbackJob_fakeAsync is set
function! s:fallbackJob_jobSend(jobStatus, text)
    call ZFJobFuncCall(get(a:jobStatus['jobImplData']['fallbackJob_fakeAsync'], 'notifySend', ''), [a:jobStatus, a:text])
endfunction
" only called when jobImplData.fallbackJob_fakeAsync is set
function! s:fallbackJob_jobStop(jobStatus, exitCode)
    call ZFJobFuncCall(get(a:jobStatus['jobImplData']['fallbackJob_fakeAsync'], 'notifyStop', ''), [a:jobStatus, a:exitCode])
endfunction

function! ZFJobFallback_notifyOutput(jobStatus, textList, type)
    if a:jobStatus['jobId'] > 0
        call ZFJobImpl_onOutput(a:jobStatus, a:textList, a:type)
    endif
endfunction

function! ZFJobFallback_notifyExit(jobStatus, exitCode)
    if a:jobStatus['jobId'] > 0
        call ZFJobImpl_onExit(a:jobStatus, a:exitCode)
    endif
endfunction


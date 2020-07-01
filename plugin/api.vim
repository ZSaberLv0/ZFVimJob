
let g:ZFJOBSTOP = 'JOBSTOP'
let g:ZFJOBTIMEOUT = 'JOBTIMEOUT'

if !exists('g:ZFJobVerboseLog')
    let g:ZFJobVerboseLog = []
endif
if !exists('g:ZFJobVerboseLogEnable')
    let g:ZFJobVerboseLogEnable = 0
endif

" ============================================================
function! ZFJobAvailable()
    return !empty(g:ZFVimJobImpl)
endfunction

" param can be jobCmd or jobOption: {
"   'jobCmd' : 'job cmd, or vim `function(jobStatus)` that return {output:xxx, exitCode:0}',
"   'jobCwd' : 'optional, cwd to run the job',
"   'onLog' : 'optional, func(jobStatus, log)',
"   'onOutputFilter' : 'optional, func(jobStatus, text, type[stdout/stderr]), return modified text or empty to discard',
"   'onOutput' : 'optional, func(jobStatus, text, type[stdout/stderr])',
"   'onEnter' : 'optional, func(jobStatus)',
"   'onExit' : 'optional, func(jobStatus, exitCode)',
"   'jobOutputLimit' : 'optional, max line of jobOutput that would be stored in jobStatus, default is 2000',
"   'jobLogEnable' : 'optional, jobLog would be recorded',
"   'jobEncoding' : 'optional, if supplied, encoding conversion would be made before passing output text',
"   'jobTimeout' : 'optional, if supplied, ZFJobStop would be called with g:ZFJOBTIMEOUT',
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

function! ZFJobStop(jobId, ...)
    return s:jobStop(ZFJobStatus(a:jobId), '' . get(a:, 1, g:ZFJOBSTOP), 1)
endfunction

function! ZFJobSend(jobId, text)
    return s:jobSend(a:jobId, a:text)
endfunction

" return: {
"   'jobId' : -1,
"   'jobOption' : {},
"   'jobOutput' : [],
"   'jobLog' : [],
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

function! ZFJobInfo(jobStatus)
    return ZFJobFuncInfo(get(get(a:jobStatus, 'jobOption', {}), 'jobCmd', ''))
endfunction

function! ZFJobLog(jobId, log)
    let jobStatus = ZFJobStatus(a:jobId)
    if !empty(jobStatus)
        call s:jobLog(jobStatus, a:log)
    endif
endfunction

" ============================================================
" {
"   'jobStart' : 'func(jobStatus, onOutput(text, type[stdout/stderr]), onExit(exitCode)), return 0/1',
"   'jobStop' : 'func(jobStatus), return 0/1',
"   'jobSend' : 'optional, func(jobStatus, text), return 0/1',
" }
if !exists('g:ZFVimJobImpl')
    let g:ZFVimJobImpl = {}
endif

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
        let exist = 0
        for jobStatus in values(s:jobMap)
            if jobStatus['jobId'] == s:jobIdCur
                let exist = 1
                break
            endif
        endfor
        if exist
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
    if g:ZFJobVerboseLogEnable
        call add(g:ZFJobVerboseLog, s:jobLogFormat(a:jobStatus, a:log))
    endif
    if get(a:jobStatus['jobOption'], 'jobLogEnable', 0)
        let log = s:jobLogFormat(a:jobStatus, a:log)
        call add(a:jobStatus['jobLog'], log)
        call ZFJobFuncCall(get(a:jobStatus['jobOption'], 'onLog', ''), [a:jobStatus, log])
    endif
endfunction

function! s:jobRemove(jobId)
    if exists('s:jobMap[a:jobId]')
        return remove(s:jobMap, a:jobId)
    else
        return {}
    endif
endfunction

function! s:jobStart(param)
    if type(a:param) == type('') || ZFJobFuncCallable(a:param)
        let jobOption = {
                    \   'jobCmd' : a:param,
                    \ }
    elseif type(a:param) == type({})
        let jobOption = copy(a:param)
    else
        echo '[ZFVimJob] unsupported param type: ' . type(a:param)
        return -1
    endif

    if empty(get(jobOption, 'jobCmd', ''))
        echo '[ZFVimJob] empty jobCmd'
        return -1
    endif

    if empty(g:ZFVimJobImpl)
        redraw!
        if get(jobOption, 'jobFallback', 1)
            return ZFJobFallback(jobOption)
        endif
        echo '[ZFVimJob] no job impl available'
        return -1
    endif

    if type(jobOption['jobCmd']) != type('') && ZFJobFuncCallable(jobOption['jobCmd'])
        return ZFJobFallback(jobOption)
    endif

    let jobStatus = {
                \   'jobId' : -1,
                \   'jobOption' : jobOption,
                \   'jobOutput' : [],
                \   'jobLog' : [],
                \   'exitCode' : '',
                \   'jobImplData' : copy(get(jobOption, 'jobImplData', {})),
                \ }
    let success = ZFJobFuncCall(g:ZFVimJobImpl['jobStart'], [
                \   jobStatus
                \ , ZFJobFunc(function('s:onOutput'), [jobStatus])
                \ , ZFJobFunc(function('s:onExit'), [jobStatus])
                \ ])
    if !success
        redraw!
        echo '[ZFVimJob] unable to start job: ' . ZFJobInfo(jobStatus)
        return -1
    endif

    if get(jobOption, 'jobTimeout', 0) > 0 && has('timers')
        let jobStatus['jobImplData']['jobTimeoutId'] = ZFJobTimerStart(jobOption['jobTimeout'], ZFJobFunc(function('s:onTimeout'), [jobStatus]))
    endif

    let jobId = s:jobIdNext()
    let jobStatus['jobId'] = jobId
    call s:jobLog(jobStatus, 'start: `' . ZFJobInfo(jobStatus) . '`')
    let s:jobMap[jobId] = jobStatus

    call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])
    return jobId
endfunction

function! s:jobStop(jobStatus, exitCode, callImpl)
    if empty(a:jobStatus)
        return 0
    endif

    call s:jobLog(a:jobStatus, 'stop with exitCode: ' . a:exitCode . ': `' . ZFJobInfo(a:jobStatus) . '`')

    if a:jobStatus['jobId'] == 0
        let jobStatus = a:jobStatus
    else
        let jobStatus = s:jobRemove(a:jobStatus['jobId'])
        if empty(jobStatus)
            return 0
        endif
    endif

    let jobTimeoutId = get(jobStatus['jobImplData'], 'jobTimeoutId', -1)
    if jobTimeoutId != -1
        call ZFJobTimerStop(jobTimeoutId)
        unlet jobStatus['jobImplData']['jobTimeoutId']
    endif

    if a:callImpl
        let ret = ZFJobFuncCall(g:ZFVimJobImpl['jobStop'], [jobStatus])
    else
        let ret = 1
    endif

    let jobStatus['exitCode'] = a:exitCode
    call ZFJobFuncCall(get(jobStatus['jobOption'], 'onExit', ''), [jobStatus, a:exitCode])
    call ZFJobOutputCleanup(a:jobStatus)

    let jobStatus['jobId'] = -1
    return ret
endfunction

function! s:jobEncoding(jobStatus)
    if !exists('*iconv')
        return ''
    endif
    return get(a:jobStatus['jobOption'], 'jobEncoding', '')
endfunction

function! s:jobSend(jobId, text)
    let jobStatus = ZFJobStatus(a:jobId)
    if empty(jobStatus)
        return 0
    endif
    let Fn_jobSend = get(g:ZFVimJobImpl, 'jobSend', '')
    if empty(Fn_jobSend)
        return 0
    endif

    call s:jobLog(jobStatus, 'send: ' . a:text)
    let jobEncoding = s:jobEncoding(jobStatus)
    if empty(jobEncoding)
        let text = a:text
    else
        let text = iconv(a:text, &encoding, jobEncoding)
    endif

    return ZFJobFuncCall(Fn_jobSend, [jobStatus, text])
endfunction

function! s:onOutput(jobStatus, text, type)
    let text = a:text
    if get(g:, 'ZFVimJobFixTermSpecialChar', 1)
        let text = substitute(text, "\x1b\[[0-9;]*[a-zA-Z]", '', 'g')
        let text = substitute(text, "\x18", '', 'g')
    endif

    let jobEncoding = s:jobEncoding(a:jobStatus)
    if !empty(jobEncoding)
        let text = iconv(text, jobEncoding, &encoding)
    endif

    if !empty(get(a:jobStatus['jobOption'], 'onOutputFilter', ''))
        let text = ZFJobFuncCall(a:jobStatus['jobOption']['onOutputFilter'], [a:jobStatus, text, a:type])
        if empty(text)
            return
        endif
    endif

    call s:jobLog(a:jobStatus, 'output [' . a:type . ']: ' . text)
    call add(a:jobStatus['jobOutput'], text)
    let jobOutputLimit = get(a:jobStatus['jobOption'], 'jobOutputLimit', 2000)
    if jobOutputLimit >= 0 && len(a:jobStatus['jobOutput']) > jobOutputLimit
        call remove(a:jobStatus['jobOutput'], jobOutputLimit)
    endif

    call ZFJobFuncCall(get(a:jobStatus['jobOption'], 'onOutput', ''), [a:jobStatus, text, a:type])
    call ZFJobOutput(a:jobStatus, text, a:type)
endfunction
function! s:onExit(jobStatus, exitCode)
    call s:jobStop(a:jobStatus, a:exitCode, 0)
endfunction
function! s:onTimeout(jobStatus, ...)
    if exists("jobStatus['jobImplData']['jobTimeoutId']")
        unlet jobStatus['jobImplData']['jobTimeoutId']
    endif
    call ZFJobStop(a:jobStatus['jobId'], g:ZFJOBTIMEOUT)
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

" ============================================================
function! ZFJobFallback(param)
    if type(a:param) == type('') || ZFJobFuncCallable(a:param)
        let jobOption = {
                    \   'jobCmd' : a:param,
                    \ }
    elseif type(a:param) == type({})
        let jobOption = copy(a:param)
    else
        echo '[ZFVimJob] unsupported param type: ' . type(a:param)
        return -1
    endif

    let jobStatus = {
                \   'jobId' : 0,
                \   'jobOption' : jobOption,
                \   'jobOutput' : [],
                \   'jobLog' : [],
                \   'exitCode' : '',
                \   'jobImplData' : copy(get(jobOption, 'jobImplData', {})),
                \ }

    call s:jobLog(jobStatus, 'start (fallback): `' . ZFJobInfo(jobStatus) . '`')

    let T_jobCmd = get(jobOption, 'jobCmd', '')
    if type(T_jobCmd) == type('')
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])

        let jobCmd = T_jobCmd
        if !empty(get(jobOption, 'jobCwd', ''))
            let jobCmd = 'cd "' . jobOption['jobCwd'] . '" && ' . jobCmd
        endif
        let result = system(jobCmd)
        let exitCode = '' . v:shell_error
    elseif ZFJobFuncCallable(T_jobCmd)
        call ZFJobFuncCall(get(jobStatus['jobOption'], 'onEnter', ''), [jobStatus])

        let result = ''
        let exitCode = '0'
        if exists('*execute')
            try
                let result = execute('let T_result = ZFJobFuncCall(T_jobCmd, [jobStatus])', '')
            catch
                let result = v:exception
                let exitCode = '-1'
            endtry
        else
            try
                redir => result
                let T_result = ZFJobFuncCall(T_jobCmd, [jobStatus])
            catch
                let result = v:exception
            finally
                redir END
            endtry
        endif
        if exists('T_result') && type(T_result) == type({}) && exists("T_result['output']") && exists("T_result['exitCode']")
            let result = T_result['output']
            let exitCode = '' . T_result['exitCode']
        endif
    else
        call s:jobLog(jobStatus, 'invalid jobCmd')
        return -1
    endif

    let jobEncoding = s:jobEncoding(jobStatus)
    for output in split(result, "\n")
        if empty(jobEncoding)
            let text = output
        else
            let text = iconv(output, jobEncoding, &encoding)
        endif
        call s:onOutput(jobStatus, text, 'stdout')
    endfor

    call s:onExit(jobStatus, exitCode)
    if exitCode != '0'
        return -1
    else
        return 0
    endif
endfunction


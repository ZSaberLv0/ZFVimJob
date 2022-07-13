if !exists('*job_start') || !has('channel') || !has('patch-7.4.1590') || !has('timers')
    finish
endif
if !empty(get(g:, 'ZFJobImpl', {}))
    finish
endif

" {
"   'jobImplIdNumber/jobImplChannelNumber' : {
"     'jobImplId' : '',
"     'jobImplIdNumber' : '',
"     'jobImplChannel' : '',
"     'jobImplChannelNumber' : '',
"     'onOutput' : '',
"     'onExit' : '',
"   }
" }
if !exists('s:jobImplIdMap')
    let s:jobImplIdMap = {}
endif
if !exists('s:jobImplChannelMap')
    let s:jobImplChannelMap = {}
endif

if exists('*string')
    function! s:toString(a)
        return substitute(string(a:a), '\n', '', 'g')
    endfunction
elseif exists('*execute')
    function! s:toString(a)
        return substitute(execute('echo a:a'), '\n', '', 'g')
    endfunction
else
    function! s:toString(a)
        try
            redir => s
            silent echo a:a
        finally
            redir END
        endtry
        return substitute(s, '\n', '', 'g')
    endfunction
endif
function! s:traitNumber(jobImplId)
    silent! let s = s:toString(a:jobImplId)
    return substitute(s, '^.\{-}\([0-9]\+\).\{-}$', '\1', '')
endfunction
function! s:jobImplIdNumber(jobImplId)
    return s:traitNumber(a:jobImplId)
endfunction
function! s:jobImplChannelNumber(jobImplChannel)
    return s:traitNumber(a:jobImplChannel)
endfunction

function! s:jobStart(jobStatus, onOutput, onExit)
    " use `mode=raw` seems to solve:
    "   https://github.com/vim/vim/issues/1320
    " also, search `queuedXxx` in this file,
    " which use timer to queue and delay output and exit callback,
    " to solve the above issue
    let jobImplOption = {
                \   'out_cb' : function('s:vim_out_cb'),
                \   'err_cb' : function('s:vim_err_cb'),
                \   'exit_cb' : function('s:vim_exit_cb'),
                \   'mode' : 'raw',
                \ }
    if !empty(get(a:jobStatus['jobOption'], 'jobCwd', ''))
        let jobImplOption['cwd'] = a:jobStatus['jobOption']['jobCwd']
    endif

    if v:version <= 800
        " for some weird vim version,
        " `python "a.py"` would fail because of double quotes
        " causing `no such file "a.py"`
        let jobCmd = ZFJobCmdToList(a:jobStatus['jobOption']['jobCmd'])
    else
        let jobCmd = a:jobStatus['jobOption']['jobCmd']
    endif
    try
        let jobImplId = job_start(jobCmd, jobImplOption)
    catch
        let jobImplId = {}
    endtry
    if empty(jobImplId) || job_status(jobImplId) != 'run'
        return 0
    endif
    let jobImplChannel = job_getchannel(jobImplId)
    if empty(jobImplChannel) || string(jobImplChannel) == 'channel fail'
        call job_stop(jobImplId)
        return 0
    endif
    let a:jobStatus['jobImplData']['jobImplId'] = jobImplId
    let a:jobStatus['jobImplData']['jobImplChannel'] = jobImplChannel

    let jobImplIdNumber = s:jobImplIdNumber(jobImplId)
    let jobImplChannelNumber = s:jobImplChannelNumber(jobImplChannel)
    let jobImplState = {
                \   'jobImplId' : jobImplId,
                \   'jobImplIdNumber' : jobImplIdNumber,
                \   'jobImplChannel' : jobImplChannel,
                \   'jobImplChannelNumber' : jobImplChannelNumber,
                \   'onOutput' : a:onOutput,
                \   'onExit' : a:onExit,
                \   'queuedTimerId' : -1,
                \   'queuedOutput' : [],
                \   'queuedExitCode' : '',
                \   'queuedExitFlag' : 0,
                \ }
    let s:jobImplIdMap[jobImplIdNumber] = jobImplState
    let s:jobImplChannelMap[jobImplChannelNumber] = jobImplState
    return 1
endfunction

function! s:jobStop(jobStatus)
    let jobImplId = a:jobStatus['jobImplData']['jobImplId']
    let jobImplChannel = a:jobStatus['jobImplData']['jobImplChannel']
    let jobImplIdNumber = s:jobImplIdNumber(jobImplId)
    let jobImplChannelNumber = s:jobImplChannelNumber(jobImplChannel)
    if exists('s:jobImplIdMap[jobImplIdNumber]')
        let jobImplState = s:jobImplIdMap[jobImplIdNumber]
        if jobImplState['queuedTimerId'] != -1
            call ZFJobTimerStop(jobImplState['queuedTimerId'])
            let jobImplState['queuedTimerId'] = -1
        endif
        unlet s:jobImplIdMap[jobImplIdNumber]
    endif
    if exists('s:jobImplChannelMap[jobImplChannelNumber]')
        unlet s:jobImplChannelMap[jobImplChannelNumber]
    endif
    if ch_status(a:jobStatus['jobImplData']['jobImplChannel']) == 'open'
        try
            silent! call ch_close(a:jobStatus['jobImplData']['jobImplChannel'])
        endtry
    endif
    call job_stop(a:jobStatus['jobImplData']['jobImplId'])
    return 1
endfunction

function! s:jobSend(jobStatus, text)
    let jobImplChannel = a:jobStatus['jobImplData']['jobImplChannel']
    call ch_sendraw(jobImplChannel, a:text)
    return 1
endfunction

function! s:vim_out_cb(jobImplChannel, msg, ...)
    let jobImplChannelNumber = s:jobImplChannelNumber(a:jobImplChannel)
    let jobImplState = get(s:jobImplChannelMap, jobImplChannelNumber, {})
    if empty(jobImplState)
        return
    endif
    call add(jobImplState['queuedOutput'], [a:msg, 'stdout'])
    call s:queuedRun(jobImplState)
endfunction
function! s:vim_err_cb(jobImplChannel, msg, ...)
    let jobImplChannelNumber = s:jobImplChannelNumber(a:jobImplChannel)
    let jobImplState = get(s:jobImplChannelMap, jobImplChannelNumber, {})
    if empty(jobImplState)
        return
    endif
    call add(jobImplState['queuedOutput'], [a:msg, 'stderr'])
    call s:queuedRun(jobImplState)
endfunction
function! s:vim_exit_cb(jobImplId, exitCode, ...)
    let jobImplIdNumber = s:jobImplIdNumber(a:jobImplId)
    let jobImplState = get(s:jobImplIdMap, jobImplIdNumber, {})
    if empty(jobImplState)
        return
    endif
    let jobImplState['queuedExitCode'] = '' . a:exitCode
    call s:queuedRun(jobImplState)
endfunction
function! s:queuedRun(jobImplState)
    if a:jobImplState['queuedTimerId'] != -1
        return
    endif
    let a:jobImplState['queuedTimerId'] = ZFJobTimerStart(10, ZFJobFunc(function('s:queuedRunCallback'), [a:jobImplState]))
endfunction
function! s:queuedRunCallback(jobImplState, ...)
    let a:jobImplState['queuedTimerId'] = -1
    while !empty(a:jobImplState['queuedOutput'])
        let queuedOutput = a:jobImplState['queuedOutput']
        let a:jobImplState['queuedOutput'] = []
        for item in queuedOutput
            call ZFJobFuncCall(a:jobImplState['onOutput'], [split(item[0], "\n"), item[1]])
        endfor
    endwhile
    if !a:jobImplState['queuedExitFlag']
        let a:jobImplState['queuedExitFlag'] = 1
        if a:jobImplState['queuedExitCode'] != ''
            call s:queuedRun(a:jobImplState)
        endif
        return
    endif

    if empty(remove(s:jobImplIdMap, a:jobImplState['jobImplIdNumber']))
        return
    endif
    call remove(s:jobImplChannelMap, a:jobImplState['jobImplChannelNumber'])

    if ch_status(a:jobImplState['jobImplChannel']) == 'open'
        try
            silent! call ch_close(a:jobImplState['jobImplChannel'])
        endtry
    endif
    call ZFJobFuncCall(a:jobImplState['onExit'], [a:jobImplState['queuedExitCode']])
endfunction

let g:ZFJobImpl = {
            \   'jobStart' : function('s:jobStart'),
            \   'jobStop' : function('s:jobStop'),
            \   'jobSend' : function('s:jobSend'),
            \ }


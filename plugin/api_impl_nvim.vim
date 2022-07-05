if !exists('*jobstart')
    finish
endif
if !empty(get(g:, 'ZFVimJobImpl', {}))
    finish
endif

" {
"   'jobImplId' : {
"     'onOutput' : '',
"     'onExit' : '',
"     'outputFix' : '',
"   }
" }
if !exists('s:jobImplStateMap')
    let s:jobImplStateMap = {}
endif

function! s:jobStart(jobStatus, onOutput, onExit)
    let jobImplOption = {
                \   'on_stdout' : function('s:nvim_on_stdout'),
                \   'on_stderr' : function('s:nvim_on_stderr'),
                \   'on_exit' : function('s:nvim_on_exit'),
                \ }
    if !empty(get(a:jobStatus['jobOption'], 'jobCwd', ''))
        let jobImplOption['cwd'] = a:jobStatus['jobOption']['jobCwd']
    endif

    try
        let jobImplId = jobstart(a:jobStatus['jobOption']['jobCmd'], jobImplOption)
    catch
        let jobImplId = -1
    endtry
    if jobImplId == 0 || jobImplId == -1
        return 0
    endif
    let a:jobStatus['jobImplData']['jobImplId'] = jobImplId
    let s:jobImplStateMap[jobImplId] = {
                \   'onOutput' : a:onOutput,
                \   'onExit' : a:onExit,
                \   'outputFix' : '',
                \ }
    return 1
endfunction

function! s:jobStop(jobStatus)
    let jobImplId = a:jobStatus['jobImplData']['jobImplId']
    if exists('s:jobImplStateMap[jobImplId]')
        call remove(s:jobImplStateMap, jobImplId)
    endif
    call jobstop(jobImplId)
    return 1
endfunction

function! s:jobSend(jobStatus, text)
    call chansend(a:jobStatus['jobImplData']['jobImplId'], a:text)
    return 1
endfunction

function! s:nvim_on_stdout(jobImplId, msgList, ...)
    call s:nvim_outputFix(a:jobImplId, a:msgList, 'stdout')
endfunction
function! s:nvim_on_stderr(jobImplId, msgList, ...)
    call s:nvim_outputFix(a:jobImplId, a:msgList, 'stderr')
endfunction
function! s:nvim_on_exit(jobImplId, exitCode, ...)
    if !exists('s:jobImplStateMap[a:jobImplId]')
        return
    endif
    let jobImplState = remove(s:jobImplStateMap, a:jobImplId)
    call ZFJobFuncCall(jobImplState['onExit'], [a:exitCode])
endfunction

let g:ZFVimJobImpl = {
            \   'jobStart' : function('s:jobStart'),
            \   'jobStop' : function('s:jobStop'),
            \   'jobSend' : function('s:jobSend'),
            \ }

" ============================================================
" output end:
"   ['aaa', 'bbb', '']
" output truncated:
"   ['aaa', 'bb']
"   ['b', '']
function! s:nvim_outputFix(jobImplId, msgList, type)
    let jobImplState = get(s:jobImplStateMap, a:jobImplId, {})
    if empty(jobImplState)
        return
    endif

    if jobImplState['outputFix'] != ''
        if len(a:msgList) > 0
            let a:msgList[0] = jobImplState['outputFix'] . a:msgList[0]
        else
            call insert(a:msgList, jobImplState['outputFix'], 0)
        endif
        let jobImplState['outputFix'] = ''
    endif

    if len(a:msgList) >= 2
        if a:msgList[len(a:msgList) - 1] == ''
            call remove(a:msgList, len(a:msgList) - 1)
        else
            let jobImplState['outputFix'] = remove(a:msgList, len(a:msgList) - 1)
        endif
    endif

    call ZFJobFuncCall(jobImplState['onOutput'], [a:msgList, 'stdout'])
endfunction


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

    let jobImplId = jobstart(a:jobStatus['jobOption']['jobCmd'], jobImplOption)
    if jobImplId == 0 || jobImplId == -1
        return 0
    endif
    let a:jobStatus['jobImplData']['jobImplId'] = jobImplId
    let s:jobImplStateMap[jobImplId] = {
                \   'onOutput' : a:onOutput,
                \   'onExit' : a:onExit,
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
    let jobImplState = get(s:jobImplStateMap, a:jobImplId, {})
    if empty(jobImplState)
        return
    endif

    call ZFJobFuncCall(jobImplState['onOutput'], [a:msgList, 'stdout'])
endfunction
function! s:nvim_on_stderr(jobImplId, msgList, ...)
    let jobImplState = get(s:jobImplStateMap, a:jobImplId, {})
    if empty(jobImplState)
        return
    endif

    call ZFJobFuncCall(jobImplState['onOutput'], [a:msgList, 'stderr'])
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


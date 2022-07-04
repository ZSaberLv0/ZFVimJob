
" ============================================================
" job pool utility, all params and api behavior are ensured same with ZFJobStart series
" ============================================================

if !exists('g:ZFJobPoolSize')
    let g:ZFJobPoolSize = 8
endif

" ============================================================
function! ZFJobPoolStart(param)
    return s:jobPoolStart(a:param)
endfunction

function! ZFJobPoolStop(jobPoolId, ...)
    return s:jobPoolStop(a:jobPoolId, '' . get(a:, 1, g:ZFJOBSTOP))
endfunction

function! ZFJobPoolSend(jobPoolId, text)
    return s:jobPoolSend(a:jobPoolId, a:text)
endfunction

" return: {
"   'jobId' : -1, // it's jobPoolId
"   'jobOption' : {},
"   'jobOutput' : [],
"   'exitCode' : 'ensured string type, empty if running, not empty when job finished',
"   'jobImplData' : {
"     'jobPool_jobId' : -1, // it's jobId returned by ZFJobStart
"     'jobPool_sendQueue' : [], // waiting queue of ZFJobPoolSend
"   },
" }
function! ZFJobPoolStatus(jobPoolId)
    return get(s:jobPoolMap, a:jobPoolId, {})
endfunction

function! ZFJobPoolTaskMap()
    return s:jobPoolMap
endfunction
function! ZFJobPoolTaskMapInfo()
    let ret = []
    for jobPoolStatus in values(s:jobPoolMap)
        let info = ZFJobPoolInfo(jobPoolStatus)
        call add(ret, info)
        echo info
    endfor
    return ret
endfunction

function! ZFJobPoolInfo(jobPoolStatus)
    return ZFJobInfo(a:jobPoolStatus)
endfunction

function! ZFJobPoolLog(jobPoolIdOrJobPoolStatus, log)
    if type(a:jobPoolIdOrJobPoolStatus) == type({})
        let jobPoolStatus = a:jobPoolIdOrJobPoolStatus
    else
        let jobPoolStatus = ZFJobPoolStatus(a:jobPoolIdOrJobPoolStatus)
    endif
    call ZFJobLog(jobPoolStatus, a:log)
endfunction

" ============================================================
if !exists('s:jobPoolIdCur')
    let s:jobPoolIdCur = 0
endif
if !exists('s:jobPoolMap')
    let s:jobPoolMap = {} " <jobPoolId, jobPoolStatus>
endif
if !exists('s:jobPoolRunning')
    let s:jobPoolRunning = {} " <jobPoolId, jobPoolStatus>
endif
if !exists('s:jobPoolQueue')
    let s:jobPoolQueue = [] " [jobPoolStatus]
endif

function! s:jobPoolIdNext()
    while 1
        let s:jobPoolIdCur += 1
        if s:jobPoolIdCur <= 0
            let s:jobPoolIdCur = 1
        endif
        if exists('s:jobPoolMap[s:jobPoolIdCur]')
            continue
        endif
        return s:jobPoolIdCur
    endwhile
endfunction

function! s:jobPoolRemove(jobPoolId)
    if !exists('s:jobPoolMap[a:jobPoolId]')
        return {}
    endif

    let jobPoolStatus = remove(s:jobPoolMap, a:jobPoolId)
    call remove(s:jobPoolRunning, a:jobPoolId)

    let i = len(s:jobPoolQueue) - 1
    while i >= 0
        if s:jobPoolQueue[i]['jobId'] == a:jobPoolId
            call remove(s:jobPoolQueue, i)
            break
        endif
        let i -= 1
    endwhile

    return jobPoolStatus
endfunction

function! s:jobPoolStart(param)
    if type(a:param) == type('') || type(a:param) == type(0) || ZFJobFuncCallable(a:param)
        let jobOption = {
                    \   'jobCmd' : a:param,
                    \ }
    elseif type(a:param) == type({})
        let jobOption = copy(a:param)
    else
        echo '[ZFVimJob] unsupported param type: ' . type(a:param)
        return -1
    endif

    let jobPoolStatus = {
                \   'jobId' : s:jobPoolIdNext(),
                \   'jobOption' : jobOption,
                \   'jobOutput' : [],
                \   'exitCode' : '',
                \   'jobImplData' : {
                \     'jobPool_jobId' : -1,
                \     'jobPool_sendQueue' : [],
                \   },
                \ }

    let jobOption['onOutput'] = ZFJobFunc(function('s:jobOnOutput'), [
                \   jobPoolStatus,
                \   get(jobOption, 'onOutput', {})
                \ ])
    let jobOption['onEnter'] = ZFJobFunc(function('s:jobOnEnter'), [
                \   jobPoolStatus,
                \   get(jobOption, 'onEnter', {})
                \ ])
    let jobOption['onExit'] = ZFJobFunc(function('s:jobOnExit'), [
                \   jobPoolStatus,
                \   get(jobOption, 'onExit', {})
                \ ])

    call add(s:jobPoolQueue, jobPoolStatus)
    let s:jobPoolMap[jobPoolStatus['jobId']] = jobPoolStatus

    call s:jobPoolRunNext()
    return jobPoolStatus['jobId']
endfunction

function! s:jobPoolStop(jobPoolId, exitCode)
    let jobPoolStatus = s:jobPoolRemove(a:jobPoolId)
    if empty(jobPoolStatus)
        return 0
    endif

    let jobPoolStatus['exitCode'] = a:exitCode

    if jobPoolStatus['jobImplData']['jobPool_jobId'] > 0
        let jobId = jobPoolStatus['jobImplData']['jobPool_jobId']
        let jobPoolStatus['jobImplData']['jobPool_jobId'] = -1
        call ZFJobStop(jobId, a:exitCode)
    endif

    let jobPoolStatus['jobId'] = -1
    call s:jobPoolRunNext()
    return 1
endfunction

function! s:jobPoolSend(jobPoolId, text)
    let jobPoolStatus = get(s:jobPoolRunning, a:jobPoolId, {})
    if !empty(jobPoolStatus)
        return ZFJobSend(jobPoolStatus['jobImplData']['jobPool_jobId'], a:text)
    endif
    let jobPoolStatus = get(s:jobPoolMap, a:jobPoolId, {})
    if empty(jobPoolStatus)
        return 0
    endif
    call add(jobPoolStatus['jobImplData']['jobPool_sendQueue'], a:text)
endfunction

function! s:jobPoolRunNext()
    if len(s:jobPoolRunning) >= g:ZFJobPoolSize
                \ || empty(s:jobPoolQueue)
        return
    endif
    let jobPoolStatus = remove(s:jobPoolQueue, 0)
    let s:jobPoolRunning[jobPoolStatus['jobId']] = jobPoolStatus

    let jobId = ZFJobStart(jobPoolStatus['jobOption'])
    let jobPoolStatus['jobImplData']['jobPool_jobId'] = jobId
    if jobId == -1 || jobId == 0
        let jobPoolStatus['jobImplData']['jobPool_sendQueue'] = []
    else
        for text in jobPoolStatus['jobImplData']['jobPool_sendQueue']
            call ZFJobSend(jobId, text)
        endfor
    endif

    if jobId == 0 && jobPoolStatus['jobId'] == -1
        let jobPoolStatus['jobId'] = 0
    endif

    call s:jobPoolRunNext()
endfunction

" ============================================================
" job callback wrapper
function! s:jobOnOutput(jobPoolStatus, onOutput, jobStatus, textList, type)
    if !empty(a:onOutput)
        call ZFJobFuncCall(a:onOutput, [a:jobStatus, a:textList, a:type])
    endif
    let a:jobPoolStatus['jobOutput'] = a:jobStatus['jobOutput']
endfunction

function! s:jobOnEnter(jobPoolStatus, onEnter, jobStatus)
    " tricks to ensure the two job shares same jobImplData
    call extend(a:jobPoolStatus['jobImplData'], a:jobStatus['jobImplData'])
    let a:jobStatus['jobImplData'] = a:jobPoolStatus['jobImplData']

    if !empty(a:onEnter)
        call ZFJobFuncCall(a:onEnter, [a:jobStatus])
    endif
endfunction

function! s:jobOnExit(jobPoolStatus, onExit, jobStatus, exitCode)
    call s:jobPoolRemove(a:jobPoolStatus['jobId'])
    if !empty(a:onExit)
        call ZFJobFuncCall(a:onExit, [a:jobStatus, a:exitCode])
    endif
    let a:jobPoolStatus['jobId'] = -1
    call s:jobPoolRunNext()
endfunction


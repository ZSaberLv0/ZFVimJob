
" groupJobOption: {
"   'jobList' : [
"     [
"       {
"         'jobCmd' : '',
"         'onOutput' : '',
"         'onExit' : '',
"         ...
"       },
"       ...
"     ],
"     ...
"   ],
"   'jobCmd' : 'optional, used only when jobList not supplied',
"   'jobCwd' : 'optional, if supplied, would use as default value for child ZFJobStart',
"   'onLog' : 'optional, func(groupJobStatus, log)',
"   'onOutput' : 'optional, func(groupJobStatus, text, type[stdout/stderr])',
"   'onEnter' : 'optional, func(groupJobStatus)',
"   'onExit' : 'optional, func(groupJobStatus, exitCode)',
"   'jobOutputLimit' : 'optional, max line of jobOutput that would be stored in groupJobStatus, default is 2000',
"   'jobLogEnable' : 'optional, jobLog would be recorded',
"   'jobEncoding' : 'optional, if supplied, would use as default value for child ZFJobStart',
"   'jobTimeout' : 'optional, if supplied, would use as default value for child ZFJobStart',
"   'jobFallback' : 'optional, if supplied, would use as default value for child ZFJobStart',
"   'jobImplData' : {}, // optional, if supplied, merge to groupJobStatus['jobImplData']
"
"   'groupJobTimeout' : 'optional, if supplied, ZFGroupJobStop would be called with g:ZFJOBTIMEOUT',
"   'onJobLog' : 'optional, func(groupJobStatus, jobStatus, log)',
"   'onJobOutput' : 'optional, func(groupJobStatus, jobStatus, text, type[stdout/stderr])',
"   'onJobExit' : 'optional, func(groupJobStatus, jobStatus, exitCode)',
" }
"
" jobList:
" contain each child job group,
" child job group would be run one by one only when previous exit successfully,
" while grand child within child job group would be run concurrently
"
" return:
" * -1 if failed
" * 0 if fallback to `system()`
" * groupJobId if success (ensured greater than 0)
function! ZFGroupJobStart(groupJobOption)
    return s:groupJobStart(a:groupJobOption)
endfunction

function! ZFGroupJobStop(groupJobId, ...)
    return s:groupJobStop(ZFGroupJobStatus(a:groupJobId), {}, '' . get(a:, 1, g:ZFJOBSTOP))
endfunction

function! ZFGroupJobSend(groupJobId, text)
    let groupJobStatus = ZFGroupJobStatus(a:groupJobId)
    if empty(groupJobStatus)
        return 0
    endif
    let sendCount = 0
    for jobStatusList in groupJobStatus['jobStatusList']
        for jobStatus in jobStatusList
            call ZFJobSend(jobStatus['jobId'], a:text)
            let sendCount += 1
        endfor
    endfor
    return sendCount
endfunction

" groupJobStatus : {
"   'jobId' : '',
"   'jobOption' : {},
"   'jobOutput' : [],
"   'jobLog' : [],
"   'exitCode' : 'ensured string type, empty if running, not empty when job finished',
"   'jobStatusFailed' : {},
"   'jobIndex' : 0,
"   'jobStatusList' : [[{jobStatus}], [{jobStatus}, {jobStatus}]],
"   'jobImplData' : {},
" }
" child jobStatus jobImplData: {
"   'groupJobId' : '',
"   'groupJobChildState' : '1: running, 0: successFinished, -1: failed',
"   'groupJobChildIndex' : 0,
"   'groupJobChildSubIndex' : 0,
" }
function! ZFGroupJobStatus(groupJobId)
    return get(s:groupJobMap, a:groupJobId, {})
endfunction

function! ZFGroupJobTaskMap()
    return s:groupJobMap
endfunction

function! ZFGroupJobInfo(groupJobStatus)
    if !exists("a:groupJobStatus['jobOption']['jobList']")
        return ZFJobInfo(a:groupJobStatus)
    endif
    let jobStatusList = a:groupJobStatus['jobStatusList']
    if !empty(jobStatusList)
        let index = len(jobStatusList) - 1
        while index != -1
            if !empty(jobStatusList[index])
                return ZFJobInfo(jobStatusList[index][-1])
            endif
            let index -= 1
        endwhile
    endif
    let jobList = a:groupJobStatus['jobOption']['jobList']
    if !empty(jobList) && !empty(jobList[0])
        if type(jobList[0]) == type([])
            return ZFJobInfo(jobList[0][0])
        elseif type(jobList[0]) == type({})
            return ZFJobInfo(jobList[0])
        endif
    endif
    return ''
endfunction

function! ZFGroupJobLog(groupJobId, log)
    let groupJobStatus = ZFGroupJobStatus(a:groupJobId)
    if !empty(groupJobStatus)
        call s:groupJobLog(groupJobStatus, a:log)
    endif
endfunction

" ============================================================
if !exists('s:groupJobIdCur')
    let s:groupJobIdCur = 0
endif
if !exists('s:groupJobMap')
    let s:groupJobMap = {}
endif

function! s:groupJobIdNext()
    while 1
        let s:groupJobIdCur += 1
        if s:groupJobIdCur <= 0
            let s:groupJobIdCur = 1
        endif
        let exist = 0
        for groupJobStatus in values(s:groupJobMap)
            if groupJobStatus['jobId'] == s:groupJobIdCur
                let exist = 1
                break
            endif
        endfor
        if exist
            continue
        endif
        return s:groupJobIdCur
    endwhile
endfunction

function! s:groupJobRemove(groupJobId)
    if exists('s:groupJobMap[a:groupJobId]')
        return remove(s:groupJobMap, a:groupJobId)
    else
        return {}
    endif
endfunction

if exists('*strftime')
    function! s:groupJobLogFormat(groupJobStatus, log)
        return strftime('%H:%M:%S') . ' groupJob ' . a:groupJobStatus['jobId'] . ' ' . a:log
    endfunction
else
    function! s:groupJobLogFormat(groupJobStatus, log)
        return 'groupJob ' . a:groupJobStatus['jobId'] . ' ' . a:log
    endfunction
endif
function! s:groupJobLog(groupJobStatus, log)
    if g:ZFJobVerboseLogEnable
        call add(g:ZFJobVerboseLog, s:groupJobLogFormat(a:groupJobStatus, a:log))
    endif
    if get(a:groupJobStatus['jobOption'], 'jobLogEnable', 0)
        let log = s:groupJobLogFormat(a:groupJobStatus, a:log)
        call add(a:groupJobStatus['jobLog'], log)
        call ZFJobFuncCall(get(a:groupJobStatus['jobOption'], 'onLog', ''), [a:groupJobStatus, log])
    endif
endfunction

function! s:groupJobStart(groupJobOption)
    let groupJobOption = copy(a:groupJobOption)
    if empty(get(groupJobOption, 'jobList', []))
        if empty(get(groupJobOption, 'jobCmd', ''))
            return -1
        else
            let groupJobOption['jobList'] = [[{
                        \   'jobCmd' : groupJobOption['jobCmd']
                        \ }]]
        endif
    endif
    let groupJobId = s:groupJobIdNext()
    let groupJobStatus = {
                \   'jobId' : groupJobId,
                \   'jobOption' : groupJobOption,
                \   'jobOutput' : [],
                \   'jobLog' : [],
                \   'exitCode' : '',
                \   'jobStatusFailed' : {},
                \   'jobIndex' : -1,
                \   'jobStatusList' : [],
                \   'jobImplData' : copy(get(groupJobOption, 'jobImplData', {})),
                \ }
    let groupJobStatus['jobImplData']['groupJobRunning'] = 1
    let jobStatusList = groupJobStatus['jobStatusList']
    for i in range(len(groupJobOption['jobList']))
        call add(jobStatusList, [])
    endfor
    let s:groupJobMap[groupJobId] = groupJobStatus

    call s:groupJobLog(groupJobStatus, 'start')

    call ZFJobFuncCall(get(groupJobStatus['jobOption'], 'onEnter', ''), [groupJobStatus])
    if s:groupJobRunNext(groupJobStatus) <= 0
        return -1
    endif

    if get(groupJobOption, 'groupJobTimeout', 0) > 0 && has('timers')
        let groupJobStatus['jobImplData']['groupJobTimeoutId'] = ZFJobTimerStart(
                    \ groupJobOption['groupJobTimeout'],
                    \ ZFJobFunc(function('s:onTimeout'), [groupJobStatus]))
    endif

    return groupJobId
endfunction

" return:
"   0 : all child finished
"   1 : wait for child finish
"   -1 : failed or child failed
function! s:groupJobRunNext(groupJobStatus)
    let a:groupJobStatus['jobIndex'] += 1
    let jobIndex = a:groupJobStatus['jobIndex']
    if jobIndex >= len(a:groupJobStatus['jobOption']['jobList'])
        call s:groupJobStop(a:groupJobStatus, {}, '0')
        return 0
    endif
    let jobList = a:groupJobStatus['jobOption']['jobList'][jobIndex]
    if empty(jobList)
        return -1
    endif
    if type(jobList) == type({})
        let jobList = [jobList]
    endif

    call s:groupJobLog(a:groupJobStatus, 'running group ' . jobIndex)
    let jobStatusList = a:groupJobStatus['jobStatusList'][jobIndex]

    let jobOptionDefault = {}
    if !empty(get(a:groupJobStatus['jobOption'], 'jobCwd', ''))
        let jobOptionDefault['jobCwd'] = a:groupJobStatus['jobOption']['jobCwd']
    endif
    if !empty(get(a:groupJobStatus['jobOption'], 'jobLogEnable', ''))
        let jobOptionDefault['jobLogEnable'] = a:groupJobStatus['jobOption']['jobLogEnable']
    endif
    if !empty(get(a:groupJobStatus['jobOption'], 'jobEncoding', ''))
        let jobOptionDefault['jobEncoding'] = a:groupJobStatus['jobOption']['jobEncoding']
    endif
    if !empty(get(a:groupJobStatus['jobOption'], 'jobTimeout', ''))
        let jobOptionDefault['jobTimeout'] = a:groupJobStatus['jobOption']['jobTimeout']
    endif
    if !empty(get(a:groupJobStatus['jobOption'], 'jobFallback', ''))
        let jobOptionDefault['jobFallback'] = a:groupJobStatus['jobOption']['jobFallback']
    endif

    let hasRunningChild = 0
    for jobOption in jobList
        let jobOptionTmp = extend(extend(copy(jobOptionDefault), jobOption), {
                    \   'onLog' : ZFJobFunc(function('s:onJobLog'), [a:groupJobStatus, get(jobOption, 'onLog', '')]),
                    \   'onOutput' : ZFJobFunc(function('s:onJobOutput'), [a:groupJobStatus, get(jobOption, 'onOutput', '')]),
                    \   'onExit' : ZFJobFunc(function('s:onJobExit'), [a:groupJobStatus, get(jobOption, 'onExit', '')]),
                    \ })
        if !exists("jobOptionTmp['jobImplData']")
            let jobOptionTmp['jobImplData'] = {}
        endif
        let jobOptionTmp['jobImplData']['groupJobId'] = a:groupJobStatus['jobId']
        let jobOptionTmp['jobImplData']['groupJobChildState'] = 1
        let jobOptionTmp['jobImplData']['groupJobChildIndex'] = jobIndex
        let jobOptionTmp['jobImplData']['groupJobChildSubIndex'] = len(jobStatusList)
        let jobId = ZFJobStart(jobOptionTmp)
        if jobId == 0
            continue
        endif

        let jobStatus = ZFJobStatus(jobId)
        if empty(jobStatus)
            call s:groupJobStop(a:groupJobStatus, {}, '-1')
            return -1
        endif
        call add(jobStatusList, jobStatus)
        let hasRunningChild = 1
    endfor
    return hasRunningChild
endfunction

function! s:groupJobStop(groupJobStatus, jobStatusFailed, exitCode)
    if empty(a:groupJobStatus)
        return 0
    endif

    call s:groupJobLog(a:groupJobStatus, 'stop [' . a:exitCode . ']')

    let groupJobStatus = s:groupJobRemove(a:groupJobStatus['jobId'])
    if empty(groupJobStatus)
        return 0
    endif

    let groupJobTimeoutId = get(groupJobStatus['jobImplData'], 'groupJobTimeoutId', -1)
    if groupJobTimeoutId != -1
        call ZFJobTimerStop(groupJobTimeoutId)
        unlet groupJobStatus['jobImplData']['groupJobTimeoutId']
    endif

    let groupJobStatus['jobImplData']['groupJobRunning'] = 0
    for jobStatusList in groupJobStatus['jobStatusList']
        for jobStatus in jobStatusList
            if jobStatus['jobImplData']['groupJobChildState'] == 1
                let jobStatus['jobImplData']['groupJobChildState'] = -1
                call ZFJobStop(jobStatus['jobId'], a:exitCode)
            endif
        endfor
    endfor

    let groupJobStatus['exitCode'] = a:exitCode
    let groupJobStatus['jobStatusFailed'] = a:jobStatusFailed
    call ZFJobFuncCall(get(groupJobStatus['jobOption'], 'onExit', ''), [groupJobStatus, a:exitCode])
    call ZFJobOutputCleanup(a:groupJobStatus)

    let groupJobStatus['jobId'] = -1
    return 1
endfunction

function! s:onJobLog(groupJobStatus, onLog, jobStatus, log)
    if !a:groupJobStatus['jobImplData']['groupJobRunning']
        return
    endif

    call s:groupJobLog(a:groupJobStatus, a:log)

    call ZFJobFuncCall(a:onLog, [a:jobStatus, a:log])
    call ZFJobFuncCall(get(a:groupJobStatus['jobOption'], 'onJobLog', ''), [a:groupJobStatus, a:jobStatus, a:log])
endfunction

function! s:onJobOutput(groupJobStatus, onOutput, jobStatus, text, type)
    if !a:groupJobStatus['jobImplData']['groupJobRunning']
        return
    endif

    call add(a:groupJobStatus['jobOutput'], a:text)
    let jobOutputLimit = get(a:groupJobStatus['jobOption'], 'jobOutputLimit', 2000)
    if jobOutputLimit >= 0 && len(a:groupJobStatus['jobOutput']) > jobOutputLimit
        call remove(a:groupJobStatus['jobOutput'], jobOutputLimit)
    endif

    call ZFJobFuncCall(a:onOutput, [a:jobStatus, a:text, a:type])
    call ZFJobFuncCall(get(a:groupJobStatus['jobOption'], 'onJobOutput', ''), [a:groupJobStatus, a:jobStatus, a:text, a:type])
    call ZFJobFuncCall(get(a:groupJobStatus['jobOption'], 'onOutput', ''), [a:groupJobStatus, a:text, a:type])
    call ZFJobOutput(a:groupJobStatus, a:text, a:type)
endfunction

function! s:onJobExit(groupJobStatus, onExit, jobStatus, exitCode)
    if a:jobStatus['jobImplData']['groupJobChildState'] == 1
        if a:exitCode != '0'
            let a:jobStatus['jobImplData']['groupJobChildState'] = -1
        else
            let a:jobStatus['jobImplData']['groupJobChildState'] = 0
        endif
    endif

    call ZFJobFuncCall(a:onExit, [a:jobStatus, a:exitCode])
    call ZFJobFuncCall(get(a:groupJobStatus['jobOption'], 'onJobExit', ''), [a:groupJobStatus, a:jobStatus, a:exitCode])

    if !a:groupJobStatus['jobImplData']['groupJobRunning']
        return
    endif

    if a:exitCode != '0'
        call s:groupJobStop(a:groupJobStatus, a:jobStatus, a:exitCode)
        return
    endif

    let jobIndex = a:groupJobStatus['jobIndex']
    let jobStatusList = a:groupJobStatus['jobStatusList'][jobIndex]
    if a:jobStatus['jobId'] == 0
        call add(jobStatusList, a:jobStatus)
    endif

    for jobStatus in jobStatusList
        if jobStatus['jobImplData']['groupJobChildState'] != 0
            return
        endif
    endfor

    call s:groupJobRunNext(a:groupJobStatus)
endfunction

function! s:onTimeout(groupJobStatus, ...)
    call ZFGroupJobStop(a:groupJobStatus['jobId'], g:ZFJOBTIMEOUT)
endfunction


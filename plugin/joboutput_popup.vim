
function! s:fallbackCheck()
    if !exists('*ZFPopupAvailable') || !ZFPopupAvailable()
        return 'logwin'
    else
        return ''
    endif
endfunction

function! s:init(outputStatus, jobStatus)
    let a:outputStatus['outputImplData']['popupid'] = ZFPopupCreate(get(a:jobStatus['jobOption']['outputTo'], 'popup', {}))
    let a:outputStatus['outputImplData']['popupContent'] = []
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction

function! s:cleanup(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        unlet a:outputStatus['outputImplData']['outputInfoTaskId']
    endif
    call ZFPopupClose(a:outputStatus['outputImplData']['popupid'])
endfunction

function! s:attach(outputStatus, jobStatus)
endfunction

function! s:detach(outputStatus, jobStatus)
    call s:updateOutputInfo(a:outputStatus, a:jobStatus)
endfunction

function! s:output(outputStatus, jobStatus, text, type)
    call add(a:outputStatus['outputImplData']['popupContent'], a:text)
    call s:updateOutputInfo(a:outputStatus, a:jobStatus)
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction

function! s:outputInfoTimer(outputStatus, jobStatus, ...)
    call s:updateOutputInfo(a:outputStatus, a:jobStatus)
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction
function! s:outputInfoIntervalUpdate(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        let a:outputStatus['outputImplData']['outputInfoTaskId'] = -1
    endif
    if get(a:jobStatus['jobOption']['outputTo'], 'outputInfoInterval', 0) > 0 && has('timers')
        let a:outputStatus['outputImplData']['outputInfoTaskId']
                    \ = ZFJobTimerStart(a:jobStatus['jobOption']['outputTo']['outputInfoInterval'], ZFJobFunc(function('s:outputInfoTimer'), [a:outputStatus, a:jobStatus]))
    endif
endfunction

function! s:updateOutputInfo(outputStatus, jobStatus)
    let popupid = a:outputStatus['outputImplData']['popupid']
    let popupContent = a:outputStatus['outputImplData']['popupContent']
    if empty(get(a:jobStatus['jobOption']['outputTo'], 'outputInfo', ''))
        call ZFPopupContent(popupid, popupContent)
    else
        let content = copy(popupContent)
        let Fn = a:jobStatus['jobOption']['outputTo']['outputInfo']
        if type(Fn) == type('')
            call add(content, '')
            call add(content, Fn)
        elseif ZFJobFuncCallable(Fn)
            let info = ZFJobFuncCall(Fn, [a:jobStatus])
            if !empty(info)
                call add(content, '')
                call add(content, info)
            endif
        endif
        call ZFPopupContent(popupid, content)
    endif
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['popup'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'cleanup' : function('s:cleanup'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'output' : function('s:output'),
            \ }



function! ZFJobOutput_popup_fallbackCheck()
    if !exists('*ZFPopupAvailable') || !ZFPopupAvailable()
        return 'logwin'
    else
        return ''
    endif
endfunction

function! ZFJobOutput_popup_init(outputStatus, jobStatus)
    let a:outputStatus['outputImplData']['popupid'] = ZFPopupCreate(get(a:outputStatus['outputTo'], 'popup', {}))
    let a:outputStatus['outputImplData']['popupContent'] = []
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction

function! ZFJobOutput_popup_cleanup(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        unlet a:outputStatus['outputImplData']['outputInfoTaskId']
    endif
    call ZFPopupClose(a:outputStatus['outputImplData']['popupid'])
endfunction

function! ZFJobOutput_popup_hide(outputStatus, jobStatus)
    call ZFPopupHide(a:outputStatus['outputImplData']['popupid'])
endfunction

function! ZFJobOutput_popup_output(outputStatus, jobStatus, textList, type)
    let a:outputStatus['outputImplData']['popupContent'] = copy(a:textList)

    let jobOutputLimit = get(a:jobStatus['jobOption'], 'jobOutputLimit', g:ZFJobOutputLimit)
    if jobOutputLimit >= 0 && len(a:outputStatus['outputImplData']['popupContent']) > jobOutputLimit
        call remove(a:outputStatus['outputImplData']['popupContent'], 0, len(a:outputStatus['outputImplData']['popupContent']) - jobOutputLimit - 1)
    endif

    call s:updateOutputInfo(a:outputStatus, a:jobStatus)
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
    call ZFPopupShow(a:outputStatus['outputImplData']['popupid'])
endfunction

function! ZFJobOutputImpl_outputInfoTimer(outputStatus, jobStatus, ...)
    call s:updateOutputInfo(a:outputStatus, a:jobStatus)
    call s:outputInfoIntervalUpdate(a:outputStatus, a:jobStatus)
endfunction
function! s:outputInfoIntervalUpdate(outputStatus, jobStatus)
    if get(a:outputStatus['outputImplData'], 'outputInfoTaskId', -1) != -1
        call ZFJobTimerStop(a:outputStatus['outputImplData']['outputInfoTaskId'])
        let a:outputStatus['outputImplData']['outputInfoTaskId'] = -1
    endif
    if get(a:jobStatus['jobOption']['outputTo'], 'outputInfoInterval', 0) > 0 && ZFJobTimerAvailable()
        let a:outputStatus['outputImplData']['outputInfoTaskId']
                    \ = ZFJobTimerStart(a:jobStatus['jobOption']['outputTo']['outputInfoInterval'], ZFJobFunc('ZFJobOutputImpl_outputInfoTimer', [a:outputStatus, a:jobStatus]))
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
        if type(Fn) == g:ZFJOB_T_STRING
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
            \   'fallbackCheck' : function('ZFJobOutput_popup_fallbackCheck'),
            \   'init' : function('ZFJobOutput_popup_init'),
            \   'cleanup' : function('ZFJobOutput_popup_cleanup'),
            \   'hide' : function('ZFJobOutput_popup_hide'),
            \   'output' : function('ZFJobOutput_popup_output'),
            \ }


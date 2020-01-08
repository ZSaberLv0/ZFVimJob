
function! s:fallbackCheck()
    if !exists('*ZFPopupAvailable') || !ZFPopupAvailable()
        return 'logwin'
    else
        return ''
    endif
endfunction

function! s:init(outputId, outputStatus, jobStatus)
    let a:outputStatus['outputImplData']['popupid'] = ZFPopupCreate(get(a:jobStatus['jobOption']['outputTo'], 'popup', {}))
    let a:outputStatus['outputImplData']['popupContent'] = []
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    call ZFPopupClose(a:outputStatus['outputImplData']['popupid'])
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
    call s:updateOutputInfo(a:outputId, a:outputStatus, a:jobStatus)
endfunction

function! s:output(outputId, outputStatus, jobStatus, text)
    call add(a:outputStatus['outputImplData']['popupContent'], a:text)
    call s:updateOutputInfo(a:outputId, a:outputStatus, a:jobStatus)
endfunction

function! s:updateOutputInfo(outputId, outputStatus, jobStatus)
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



function! s:fallbackCheck()
    if !exists('*ZFPopupAvailable') || !ZFPopupAvailable()
        return 'logwin'
    else
        return ''
    endif
endfunction

function! s:init(outputId, outputStatus, jobStatus)
endfunction

function! s:attach(outputId, outputStatus, jobStatus)
    let outputTo = a:jobStatus['jobOption']['outputTo']
    if a:outputStatus['outputTaskCount'] == 1
        let a:outputStatus['outputImplData']['popupid'] = ZFPopupCreate(get(outputTo, 'popup', {}))
    endif
endfunction

function! s:detach(outputId, outputStatus, jobStatus)
endfunction

function! s:cleanup(outputId, outputStatus, jobStatus)
    if a:outputStatus['outputImplData']['popupid'] < 0
                \ || a:outputStatus['outputTaskCount'] != 1
        return
    endif
    call ZFPopupClose(a:outputStatus['outputImplData']['popupid'])
    let a:outputStatus['outputImplData']['popupid'] = -1
endfunction

function! s:output(outputId, outputStatus, jobStatus, text)
    if a:outputStatus['outputImplData']['popupid'] < 0
        return
    endif
    let popupid = a:outputStatus['outputImplData']['popupid']
    let content = ZFPopupContent(popupid)
    call add(content, a:text)
    call ZFPopupContent(popupid, content)
endfunction

if !exists('g:ZFJobOutputImpl')
    let g:ZFJobOutputImpl = {}
endif
let g:ZFJobOutputImpl['popup'] = {
            \   'fallbackCheck' : function('s:fallbackCheck'),
            \   'init' : function('s:init'),
            \   'attach' : function('s:attach'),
            \   'detach' : function('s:detach'),
            \   'cleanup' : function('s:cleanup'),
            \   'output' : function('s:output'),
            \ }


; experimental CGA mode 4/5/6 emulation TSR driver for Hercules HGC
; will use custom 640x300x2 mode
; assemble with yasm/nasm
;
; SPDX-License-Identifier: 0BSD
;
; Copyright (C) 2020 by Benedikt Freisen
;
; Permission to use, copy, modify, and/or distribute this software for any
; purpose with or without fee is hereby granted.
;
; THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
; WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
; MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
; ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
; WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
; ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
; OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

[bits 16]
[org 0x100]

	jmp	main

tsr10:
	cmp	ah,00h
	je	intercept_00h
	cmp	ah,0fh
	je	intercept_0fh
normal_int_10h:
	push	word [cs:int10seg]
	push	word [cs:int10ofs]
	retf

intercept_00h:
	mov	[cs:display_mode],al
	cmp	al,4
	je	cga_mode_requested
	cmp	al,5
	je	cga_mode_requested
	cmp	al,6
	je	cga_mode_requested
	cmp	al,84h
	je	cga_mode_requested
	cmp	al,85h
	je	cga_mode_requested
	cmp	al,86h
	je	cga_mode_requested
	jmp	normal_int_10h

intercept_0fh:
	cmp	byte [cs:display_mode],13h
	je	is_13h
	cmp	byte [cs:display_mode],93h
	jne	normal_int_10h
is_13h:
	mov	ah,40	; number of character columns
	mov	al,[cs:display_mode]
	mov	bl,0	; active page
	iret

cga_mode_requested:
	call	set_mode_640x300x2
	mov	al,20h
	iret

int10seg dw 0000h
int10ofs dw 0000h
display_mode db 0

; CRTC table for 640x300, 3 fields
crtc_tab db 35h,28h,2ch,07h,79h,03h,64h,6ch,02h,02h,00h,00h

; keep a signature somewhere to prevent double loading
signature db "HGCGA"

; switch to 640x300x2 Hercules mode
set_mode_640x300x2:
	push	ax
	push	dx

	; switch to mode 7
	mov	ax,7
	int	10h

	; disable video (graphics mode with page 1)
	mov	dx,3b8h
	mov	al,82h
	out	dx,al

	; set CRTC registers

	push	ds
	push	si

	push	cs
	pop	ds
	mov	si,crtc_tab

	xor	ax,ax
	cld		; will be restored by iret

crtc_loop:
	mov	dl,0b4h	; dx=3b4h
	out	dx,al
	inc	ax
	push	ax
	lodsb
	inc	dx
	out	dx,al
	pop	ax
	cmp	al,12
	jb	crtc_loop

	; allow graphics mode, upper page enabled
	mov	dl,0bfh	; dx=3bfh
	mov	al,3	; 1 if upper page disabled
	out	dx,al

	pop	si
	pop	ds


	cmp	byte [cs:display_mode],6
	ja	skip_clear_screen
	; clear screen
	push	es	; save es
	mov	ax,0b800h
	mov	es,ax	; es=0b800h
	push	di	; save di
	xor	di,di	; di=0
	xor	ax,ax	; ax=0
	push	cx	; save cx
	mov	cx,16384
	rep	stosw	; clear the entire 32KiB page
	pop	cx	; restore cx
	pop	di	; restore di
	pop	es	; restore es
skip_clear_screen:

	; enable video (graphics mode with page 1)
	mov	dl,0b8h	; dx = 3b8h
	mov	al,8ah
	out	dx,al

	pop	dx	; restore dx
	pop	ax	; restore ax

	ret

; calculate number of paragraphs to be kept resident from this label
behind_tsr_end:

main:
	; print title
	mov	dx,msg_title
	mov	ah,9
	int	21h

	; get interrupt vector for 10h (stores result in es:bx)
	mov	ax,3510h
	int	21h

	; try to figure out whether the TSR is already installed
	mov	cx,5
	mov	di,signature
	mov	si,signature
	repe	cmpsb
	; store old interrupt vector
	mov	word [int10seg],es
	mov	word [int10ofs],bx
	; install TSR if signature check failed
	jne	install_tsr

	; TSR removal requested? (case insensitive /u)
	cmp	word [81h]," /"
	jne	already_loaded
	mov	ax,[83h]
	or	al,20h
	cmp	ax,'u'+(13<<8)
	jne	already_loaded
	; restore original interrupt vector
	mov	ax,2510h
	push	ds	; save ds
	push	word [es:int10seg]
	pop	ds
	mov	dx,[es:int10ofs]
	int	21h
	; free TSR memory; TSR segment already in es
	mov	ah,49h
	int	21h
	pop	ds	; restore ds
	mov	dx,msg_success_rem
	jmp	output_msg_and_exit
already_loaded:
	mov	dx,msg_error_already_loaded
	jmp	output_msg_and_exit

install_tsr:
	; find out whether a Hercules Graphics Card is installed
	; TODO

	; go on and install the TSR
	mov	ax,2510h
	mov	dx,tsr10
	int	21h

	; print success message
	mov	dx,msg_success
	mov	ah,9
	int	21h

	; terminate and stay resident
	mov	ax,3100h
	mov	dx,(behind_tsr_end+15)>>4
	int	21h

; incompatible graphics adapter detected
incompat_vid:
	mov	dx,msg_error_incompat_vid
output_msg_and_exit:
	mov	ah,9
	int	21h
	mov	ah,0
	int	21h


msg_title db "CGA mode 4/5/6 emulator for HGC - TSR $"
msg_error_already_loaded db "already loaded",10,13,"$"
msg_success db "loaded",10,13,"$"
msg_success_rem db "removed",10,13,"$"
msg_error_incompat_vid db "error: Wrong graphics adapter",10,13,"$"

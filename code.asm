#make_bin#

#LOAD_SEGMENT=FFFFh#
#LOAD_OFFSET=0000h#

#CS=0000h#
#IP=0000h#

#DS=0000h#
#ES=0000h#

#SS=0000h#
#SP=FFFEh#

#AX=0000h#
#BX=0000h#
#CX=0000h#
#DX=0000h#
#SI=0000h#
#DI=0000h#
#BP=0000h#

;jump to the start of the code - reset address is kept at 0000:0000
;as this is only a limited simulation
        jmp     main
;jmp main - takes 3 bytes followed by nop that is 4 bytes
        nop
;int 1 is not used so 1 x4 = 00004h - it is stored with 0
        dw      0000
        dw      0000
;eoc - is used as nmi - ip value points to ad_isr and cs value will
;remain at 0000
        dw      0000
        dw      0000
;int 3 to int 255 unused so ip and cs intialized to 0000
;from 3x4 = 0000cH
		db     1012 dup(0)

		org 100h ;entry for vector number 40h in IVT
		dw startWeigh_isr
		dw 0000
		dw buzzerOff_isr
		dw 0000
		dw EOC_ADC_isr
		dw 0000

		org 1000h

    ; store the digital values of weights measured
		weights	db	3 dup(?)

		org 400h

		;8255A
		porta1 equ 00h		;Data lines of ADC
		portb1 equ 02h
		portc1 equ 04h		;ADC control signals
		creg1 equ 06h		;control register

		;8255B
		porta2 equ 08h		;stepper motor horizontal
		portb2 equ 0Ah		;stepper motor vertical
		portc2 equ 0Ch		;Output GATE1 and output LED for scan complete
		creg2 equ 0Eh		;control register

		;8259
		add1 equ 18h
		add2 equ 1Ah

;main program

main:
    cli
; intialize ds, es,ss to start of RAM
    mov       ax,0100h
    mov       ds,ax
    mov       es,ax
    mov       ss,ax
    mov       sp,0FFEH
    mov       si,0000

		;initialize 8255A
		;I/O Mode(1), Port A Mode0(00), Port A i/p(1), Port C Upper o/p(0), Port B Mode0 (0), Port B i/p(1), Port C Lower o/p(0)
		mov al,10010010b
		out creg1,al

		;initialize 8255B
		;I/O Mode(1), Port A Mode0(00), Port A o/p(0), Port C Upper o/p(0), Port B Mode0 (0), Port B o/p(0), Port C Lower o/p(0)
		mov al,10000000b
		out creg2,al

    ;initialize 8259 for 40h

		;ICW1
		mov al, 00010011b ; 3 msbs represent the address lines, they are dont cares for 8086 processor
		out add1,al

		;ICW2 - starting vector number is 40h
		mov al,01000000b
		out add2,al

		;ICW4
		mov al,00001011b ;
		out add2,al

		;OCW1 - enable all interrupts
		mov al,00000000b
		out add2,al
		; Figure out the int vector address;

		sti

idle:
    JMP idle

;end of main program


;subroutine to read 8-bit digitized voltage value of a weight from ADC
readweight PROC NEAR
    ; set up of the combination to select the inp0, inp1 or inp2



    MOV di, 0

eoc_wait:
		cmp di,1
		jne eoc_wait

ret
readweight	ENDP

buzzerOn  PROC NEAR
    mov Al,00000001b
    out	portc1,AL
    ret
buzzerOn	ENDP

;ISR for NMI from EOC of ADC0808
EOC_ADC_isr:

		;give output enable OE, PC3 is connected to OE of ADC0808
		;or al,00001000b
		;out	portc1,al

		;get the 8-bit value into al register
		in al,porta1
		mov [weights + CX],al
    MOV di, 1
iret


buzzerOff_isr:
  STI
	mov Al,00000000b
	out	portc1,AL
iret

startWeigh_isr:
    STI
    MOV CX, 0
doRead:
    CALL readweight
    INC CX
		CMP CX,3
    JNE doRead

getAvg:

  	mov inp1,30h
  	mov inp2,33h
  	mov inp3,34h

  	;SUM UP THE INPUTS
    MOV si, weights
  	mov bx,00h
  	mov al,[SI]
    INC SI
  	cbw
  	add bx,ax

  	mov al,[SI]
    INC SI
  	cbw
  	add bx,ax

  	mov al,[SI]
    INC SI
  	cbw
  	add bx,ax

  	mov ax,bx

  	;MULTIPLY SUM BY 100d ie 64h
  	mov bl,64h
  	mul bl
  	mov dx,0000h

  	;DIVIDE BY 3 TO TAKE AVG - AX CONTAINS THE AVG IN HEXA FORM AT END
  	mov bx,0003h
  	div bx

  	;CONVERT TO BCD
  	mov cl, 64h
  	div cl
  	mov bh,al
  	mov al, ah
  	mov ah,00h
  	mov cl,0ah
  	div cl
  	mov cl,04h
  	rol al,cl
  	add al,ah
  	mov bl,al
  	mov bcd,bx

  	;SEPERATE THE DIGITS
  	mov ax,bcd
  	and ax,000fh
  	mov digit1,al

  	mov ax,bcd
  	and ax,00f0h
  	mov cl,04h
  	ror ax,cl
  	mov digit2,al

  	mov ax,bcd
  	and ax,0f00h
  	mov cl,08h
  	ror ax,cl
  	mov digit3,al

  	mov ax,bcd
  	and ax,0f000h
  	mov cl,0ch
  	ror ax,cl
  	mov digit4,al



    CMP avg, 99
    JL DISPLAY
    MOV digit1, 0
    MOV digit2, 0
    MOV digit3, 0
    MOV digit4, 0
    CALL buzzerOn
DISPLAY:

  	;DISPLAY DIGITS

  	mov dl,'0'
  	add dl,digit1
  	mov ah,02h
  	int 21h

  	mov dl,'0'
  	add dl,digit2
  	mov ah,02h
  	int 21h

  	mov dl,'0'
  	add dl,digit3
  	mov ah,02h
  	int 21h

  	mov dl,'0'
  	add dl,digit4
  	mov ah,02h
  	int 21h
iret

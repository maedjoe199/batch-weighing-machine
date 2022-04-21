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

; add your code here
;jump to the start of the code - reset address is kept at 0000:0000
;as this is only a limited simulation
        jmp     st1
;jmp st1 - takes 3 bytes followed by nop that is 4 bytes
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
		dw weigh_isr
		dw 0000
		dw buzzer_isr
		dw 0000
		dw adc_isr
		dw 0000

		org 1000h
		;start of RAM
		;memory to store the 800 bytes to be obtained from the photodiodes
		data db 800 dup(0)

		;stepsequences for vertical and horizontal stepper motors
		step_h db 33h	;horizontal stepper motor
		step_v db 33h	;vertical stepper motor
		cur_row db 0	;current row of the PD array
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

		;8254
		counter0 equ 10h
		counter1 equ 12h
		counter2 equ 14h
		count_creg equ 16h

		;8259
		add1 equ 18h
		add2 equ 1Ah

;main program

st1:      cli
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

		;initialize 8254
		mov al,00110110b	;counter0 in mode3, binary
		out count_creg,al

		;load value of 5 in counter0 for ADC0808, 1Mhz
		mov al,05
		out counter0,al
		mov al,0
		out counter0,al

		;initialize 8259
		;ICW1
		mov al, 00010011b
		out add1,al

		;ICW2 - starting vector number is 40h
		mov al,01000000b
		out add2,al

		;ICW4
		mov al,00000001b
		out add2,al

		;OCW1 - enable all interrupts
		mov al,00000000b
		out add2,al

		sti

		;di made 1. In start scan ISR, di is made 0 to indicate interrupt.
		mov di,1

readswitch:
		cmp di,0
		jnz readswitch

		;si will maintain the current address where memory is being stored
		lea si,data
nextrow:
		;call the scan 5 bytes procedure 2 times
		mov cx,2
x0:		call scan5
		loop x0

		inc cur_row
		mov al,cur_row
		cmp al,80	;to check whether last row is reached
		jz eop

		;move vertical stepper motor, to move the PD array to the next row
		call move_vmotor
		;move the PD array back to the start of the row
		call h_motor_row_start

		jmp nextrow

;end of scan
eop:	;give output to scan complete LED
		mov al,00010000b 	;Scan complete LED is connected to the PC4 of 8255B
		out portc2,al		;Scan complete LED glows

		;to reset the position of photodiodes to the top-left corner
		;move the PD array to the first row.
		call move_vmotor_acw
		;move the PD array back to the start of the row
		call h_motor_row_start

;end of main program


;subroutine to store data from all 5 pds for 8 iterations i.e. 8 pixels scanned for each photodiode
scan5:
		push cx

		;beacuse 8 iterations
		mov dl,8

;this loop runs for 8 times because 8 pixels are to be read.
next_bit:
		;because 5 photodiodes to be read
		mov cx,5

		;start with 1st photodiode
		mov bx,0

;this loop run for 5 times because 5 photodiodes to be scanned
next_pd:
		;address placed on AD0, AD1, AD2 of ADC
		mov al,bl
		out portc1,al

		;this reads the 8-bit value that is obtained from the photodiode selected using bl
		call readpd

		;for next photodiode
		inc bx

		dec cx
		jnz next_pd

		;the horizontal stepper motor is rotated so that the next pixel is scanned by the photodiode
		call move_motor_next_bit

		dec dl
		jnz next_bit

		;now si which stores address location of PD1 is added by 5
		add si,5
		;rotates the horizontal stepper motor so that PD1 is at 5cm from the start of the row.
		call move_motor_next_byte

		pop cx
ret

;subroutine to read 8-bit digitized voltage value of a photodiode
readpd:

		;di is made 1 to check whether nmi_isr is executed
		mov di,1

		;give ale, PC5 of 8255 connected to ALE of ADC0808
		or al,00100000b
		out portc1, al

		;wait for half clock cycle of ADC
		nop
		nop

		;give soc  PC4 of 8255 connected to SOC of ADC 0808
		or al,00010000b
		out	portc1,al

		;wait for half clock cycle of ADC
		nop
		nop

		;make ale 0
		and al,11011111b
		out portc1,al

		;wait for half clock cycle of ADC
		nop
		nop

		;make soc 0
		and al,11101111b
		out portc1,al

eoc_wait:
		cmp di,0
		jnz eoc_wait

ret

;subroutine to rotate the horizontal stepper motor by 1 step in clockwise direction
h_motor_step:
		mov al,step_h
		out porta2, al
		call delay_1ms
		ror al,1
		mov step_h,al
ret

;subroutine to rotate the horizontal stepper motor by 1 step in anti-clockwise direction
h_motor_step_acw:
		mov al,step_h
		out porta2, al
		call delay_1ms
		rol al,1
		mov step_h,al
ret

;subroutine to move the horizontal motor forward by 1.25 mm  i.e. 250 steps of the stepper motor (step angle = 1.8 degree)
move_motor_next_bit:
		push cx

h0:		mov cx,250
		call h_motor_step
		loop h0

		pop cx
ret

;subroutine to move the horizontal motor forward by 4 cm, i.e. 8000 steps of the stepper motor (step angle = 1.8 degree)
move_motor_next_byte:
		push cx

h1:		mov cx,8000
		call h_motor_step
		loop h1

		pop cx
ret

;subroutine to move the horizontal stepper motor back to start of the row .i. 6 cm back i.e 12000 steps
h_motor_row_start:
		push cx

		;rotate al twice to the left for next step-sequence for anti-clockwise rotation
		mov al,step_h
		rol al,2
		mov step_h, al

h2:		mov cx,12000
		call h_motor_step_acw
		loop h2

		;rotate al twice to the right for next step-sequence for clockwise rotation
		mov al,step_h
		ror al,2
		mov step_h, al

		pop cx
ret

;subroutine for moving the vertical stepper motor by 1.25 mm downward(clockwise)
move_vmotor:
		push cx
		mov cx,250

v0:		mov al,step_v	;step_v contains the step-sequence for the vertical stepper motor
		out portb2, al	;portb2 of 8255B connects to vertical stepper motor
		call delay_1ms
		ror al,1
		mov step_v,al
		loop v0

		pop cx
ret

;subroutine for moving the vertical stepper motor 9.875 cm upward(anti-clockwise)
move_vmotor_acw:
		push cx
		mov cx,19750	;1mm takes 200 steps, so 9.875cm takes 19750 steps

v1:		mov al,step_v	;step_v contains the step-sequence for the vertical stepper motor
		out portb2, al	;portb2 of 8255B connects to vertical stepper motor
		call delay_1ms
		ror al,1
		mov step_v,al
		loop v1

		pop cx
ret

;subroutine for accurate delay of 1ms
delay_1ms:

		mov di, 1

		;make GATE signal high and wait for timer interrupt.
		;using BSR mode
		mov al, 00000001b
		out creg2, al

xd:		cmp di,0
		jnz xd
ret

;ISR for NMI from EOC of ADC0808
adc_isr:

		;di is decremented to show nmi isr is executed
		dec di

		;give output enable OE, PC3 is connected to OE of ADC0808
		;or al,00001000b
		;out	portc1,al

		;get the 8-bit value into al register
		in al,porta1
		mov [weights +di],al
iret


buzzer_isr:
	mov Al,00000000b
	out	portc1,AL
iret

weigh_isr:
		dec di
		;mask IR0
		mov al,00000001b
		out add2,al
iret

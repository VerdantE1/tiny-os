%include "boot.inc"

;设置加载器加载的虚拟地址boot.inc中定义为0x900
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR


jmp loader_start 

;第一个段描述符不可用设置为0
GDT_BASE:
	dd 0x00000000
	dd 0x00000000

;代码段描述符，代码由低地址向高地址扩展故前面的为低4B内存,平坦模式下，段的基址都是0
CODE_DESC:
	dd 0X0000ffff
	dd DESC_CODE_HIGH4

;栈段描述符，与数据段共享
DATA_STACK_DESC:
	dd 0x0000ffff
	dd DESC_DATA_HIGH4

;显卡段描述符，采用非平坦模式
VIDEO_DESC:
	dd 0x80000007     ;界限=(0xbfff-0xb8000)/4k=0x7,段基址设置为文本起始地址0xb8000
	dd DESC_VIDEO_HIGH4

GDT_SIZE equ $ - GDT_BASE    ;获取GDT表大小
GDT_LIMIT equ GDT_SIZE - 1    ;获取GDT表段界限
times 60 dq 0   ;预留60个段描述符

;段描述符构造完,定义选择子
SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0
SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0
SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0


;准备工作完毕,构造一个48位数据给GDTR以维护
gdt_ptr dw GDT_LIMIT
	dd GDT_BASE


loadermsg db '2 loader in real.'


;;;;;;;;;;;	CPU执行代码段	;;;;;;;;;

loader_start:
	;调用BIOS 10h号中断显示字符串
mov byte [gs:0x00],'H'
mov byte [gs:0x01],0xA4

	
	mov sp,LOADER_BASE_ADDR
	mov bp,loadermsg	  
	mov cx,17                 ;字符串长度为17
	mov ax,0x1301
	mov bx,0x001f
	mov dx,0x1800
	int 0x10

	;开始进入保护模式
	;打开A20地址线
	in al,0x92;
	or al,00000010b
	out 0x92,al




	;加载gdt
	lgdt [gdt_ptr]


	;打开CR0的PE位
	mov eax,cr0
	or eax,0x00000001
	mov cr0,eax


	;刷新流水线
	jmp dword SELECTOR_CODE:p_mode_start



;开始利用保护模式寻址写命令
[bits 32]
p_mode_start:
	mov ax,SELECTOR_DATA
	mov ds,ax
	mov es,ax
	mov ss,ax
	mov esp,LOADER_STACK_TOP
	mov ax,SELECTOR_VIDEO
	mov gs,ax
	;将各个寄存器指向所需选择子，初始化完毕;


	mov byte [gs:160],'L'
	mov byte [gs:161],0x1f
	mov byte [gs:162],'B'
	mov byte [gs:163],0x1f
	mov byte [gs:164],'Q'
	mov byte [gs:165],0x1f

	jmp $

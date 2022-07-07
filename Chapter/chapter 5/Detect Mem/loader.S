%include "boot.inc"

;loader的虚拟地址boot.inc中定义为0x900
section loader vstart=LOADER_BASE_ADDR
LOADER_STACK_TOP equ LOADER_BASE_ADDR



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





;;;;;;;;;;;;;;64个段描述符是64*8=512字节,故该地址为0x900+0x200 = 0xb00，一个好记的数字记录获取到的内存量
	total_mem_bytes dd 0



;定义gdtr指针，前2字节是界限，后4字节是地址，共6字节
gdt_ptr dw GDT_LIMIT
	dd GDT_BASE

;人工对齐:此处为0xb06,我们还需要记录ARDS结构体数量，需要ards_buf缓冲地址和ards_nr数量
	ards_buf times 244 db 0
	ards_nr dw 0


;total_mem_bytes (4) + gdt_ptr(6) + ards_buf (244) + ards_nr (2) = 256 ,现在再往下就是0xc00

;开始写指令部分


loader_start:
;	int 15h eax=0000E820h,edx = 534D4150h('SMAP') 获取内存布局
	xor ebx,ebx ;第一调用ebx为0
	mov edx,0x53d4150
	mov di,ards_buf
.e820_mem_get_loop:
	mov eax,0x0000e820  ;执行int 0x15后，eax变为0x534d4150,所以每次执行int前都要更新为子功能号
	mov ecx,20

	int 0x15
	jc .e820_failed_so_try_e801 	;若cf位为1,则有错误发生，尝试0x801子功能
	add di,cx
	inc word [ards_nr] 	;调用完后善后处理，di移动20字节，ards_nr记录++

	cmp ebx,0	;ebx判断e820是否调用完，为0调用完，不为0继续调用
	jnz .e820_mem_get_loop



;到此步骤是调用完全后，再在所有ards结构中找出最大内存块（base_add_low + length_low）
	mov cx,[ards_nr]
;遍历每个ards结构体，循环次数是ards的数量
	mov ebx,ards_buf
	xor edx,edx	;edx记录最大内存，先初始化清0
.find_max_mem_area:
;无需判断type是否为1,最大的内存块一定是可使用的
	mov eax,[ebx]
	add eax,[ebx+8]
	add ebx,20
	cmp edx,eax
;冒泡排序，找出最大，edx大于等于eax则跳过，edx小于则赋值
	jge .next_ards
	mov edx,eax

.next_ards:
	loop .find_max_mem_area
	jmp .mem_get_ok

;0xe820调用完毕，再写第二种方案


;;;;;;;;;;调用int 0x15 ~ 0xe801;;;;;;;;;;;;;
.e820_failed_so_try_e801:
	mov ax,0xe801
	int 0x15
	jc .e801_failed_so_try88  	;若当前方法失败，调用第三种方法

;1.计算低15MB内存
;ax,cx中是以KB为单位的量，bx,dx中是以64KB为单位的量
	mov cx,0x400
	mul cx
	shl edx,16
	and eax,0x0000ffff
	or edx,eax
	add edx,0x100000    ;加上预留的地址为15mb~16mb的内存空洞
	mov esi,edx

;2.计算16MB以上的内存
	xor eax,eax
	mov ax,bx
	mov ecx,0x10000
	mul ecx
	add esi,eax  ;此方法只能测出4GB以内的内存，所以32位就够了，积的高32位一定是0,故不用edx
	

	mov edx,esi ;总内存在esi，放入edx
	jmp .mem_get_ok


;;;;;;;;;;调用int 0x15 ~0x88;;;;;;;;;;;
.e801_failed_so_try88:
	mov ah,0x88
	int 0x15
	jc .error_hlt
	and eax,0x0000ffff

	mov cx,0x400
	mul cx
	shl edx,16
	or edx,eax
	add edx,0x100000	;0x88子功能只会返回1MB以上的内存，故加上下面的1MB
	jmp .mem_get_ok


.error_hlt:
	mov byte [gs:0],'W'
	mov byte [gs:2],'A'
	jmp .done


.mem_get_ok:
	mov [total_mem_bytes],edx ;将内存总量存放到内存中去
	jmp .done

.done:
	mov byte [gs:160],'D'
	mov byte [gs:162],'O'
	mov byte [gs:164],'N'
	mov byte [gs:166],'E'
	mov byte [gs:168],'!'

	jmp $

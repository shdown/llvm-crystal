require "./lib_llvm_c"

private macro def_unsafe_at_compat_shim
    def unsafe_at (i)
        return unsafe_fetch(i)
    end
end

module LibLLVM
    def self.slurp_string (pmsg : LibC::Char*)
        msg = String.new(pmsg)
        LibLLVM_C.dispose_message(pmsg)
        return msg
    end

    class IrBuffer
        def initialize (@value : LibLLVM_C::MemoryBufferRef)
        end

        def to_unsafe
            @value
        end

        def finalize
            LibLLVM_C.dispose_memory_buffer(@value)
        end

        def_equals @value
        def_hash @value
    end

    struct Instruction
        def initialize (@value : LibLLVM_C::ValueRef)
        end

        def to_unsafe
            @value
        end

        def successors
            return Successors.new(@value)
        end

        def incoming
            return Incoming.new(@value)
        end

        def_equals @value
        def_hash @value
    end

    struct BasicBlock
        def initialize (@value : LibLLVM_C::BasicBlockRef)
        end

        def to_unsafe
            @value
        end

        def instructions
            return Instructions.new(@value)
        end

        def terminator
            pins = LibLLVM_C.get_basic_block_terminator(@value)
            raise "Basic block has no terminator" unless pins
            return Instruction.new(pins)
        end

        def_equals @value
        def_hash @value
    end

    struct Signature
        def initialize (
                @ret_ty : LibLLVM_C::TypeRef,
                @params : Array(LibLLVM_C::ValueRef),
                @is_var_arg : Bool)
        end
    end

    struct Function
        def initialize (@value : LibLLVM_C::ValueRef)
        end

        def to_unsafe
            @value
        end

        def name
            pname = LibLLVM_C.get_value_name2(@value, out nname)
            return String.new(pname, nname)
        end

        def declaration?
            return LibLLVM_C.is_declaration(@value) != 0
        end

        def entry_basic_block
            return BasicBlock.new(LibLLVM_C.get_entry_basic_block(@value))
        end

        def signature
            func_ty = LibLLVM_C.type_of(@value)
            # In some reason, 'func_ty' is now a pointer-to-function type.
            if LibLLVM_C.get_type_kind(func_ty).pointer_type_kind?
                # "Dereference" it.
                func_ty = LibLLVM_C.get_element_type(func_ty)
            end

            ret_ty = LibLLVM_C.get_return_type(func_ty)
            nparams = LibLLVM_C.count_params(@value)
            params = Array(LibLLVM_C::ValueRef).build(nparams) do |buffer|
                LibLLVM_C.get_params(@value, buffer)
                nparams
            end
            is_var_arg = LibLLVM_C.is_function_var_arg(func_ty) != 0
            return Signature.new(ret_ty: ret_ty, params: params, is_var_arg: is_var_arg)
        end

        def_equals @value
        def_hash @value
    end

    class IrModule
        def initialize (@value : LibLLVM_C::ModuleRef)
        end

        def to_unsafe
            @value
        end

        def finalize
            LibLLVM_C.dispose_module(@value)
        end

        def functions
            return Functions.new(self)
        end

        def_equals @value
        def_hash @value
    end

    def self.buffer_from_file (path)
        if LibLLVM_C.create_memory_buffer_with_contents_of_file(path, out pbuf, out pmsg) != 0
            raise "Cannot open bitcode file: " + slurp_string(pmsg)
        end
        return IrBuffer.new(pbuf)
    end

    def self.module_from_buffer (buf)
        raise "Cannot parse bitcode" unless
            LibLLVM_C.parse_bitcode2(buf, out pmodule) == 0
        return IrModule.new(pmodule)
    end

    private struct Successors
        include Indexable(BasicBlock)

        def initialize (@instr : LibLLVM_C::ValueRef)
            @size = LibLLVM_C.get_num_successors(@instr)
        end

        def size
            return @size
        end

        def unsafe_fetch (i)
            return BasicBlock.new(LibLLVM_C.get_successor(@instr, i))
        end

        def_unsafe_at_compat_shim
    end

    private struct Incoming
        include Indexable(LibLLVM_C::ValueRef)

        def initialize (@instr : LibLLVM_C::ValueRef)
            @size = LibLLVM_C.count_incoming(@instr)
        end

        def size
            return @size
        end

        def unsafe_fetch (i)
            return {
                BasicBlock.new(LibLLVM_C.get_incoming_block(@instr, i)),
                LibLLVM_C.get_incoming_value(@instr, i)
            }
        end

        def_unsafe_at_compat_shim
    end

    private struct Functions
        include Enumerable(Function)

        def initialize (@owner : IrModule)
        end

        def each
            pfunc = LibLLVM_C.get_first_function(@owner)
            while pfunc
                yield Function.new(pfunc)
                pfunc = LibLLVM_C.get_next_function(pfunc)
            end
        end
    end

    private struct Instructions
        include Enumerable(Instruction)

        def initialize (@block : LibLLVM_C::BasicBlockRef)
        end

        def each
            pins = LibLLVM_C.get_first_instruction(@block)
            while pins
                yield Instruction.new(pins)
                pins = LibLLVM_C.get_next_instruction(pins)
            end
        end
    end

end

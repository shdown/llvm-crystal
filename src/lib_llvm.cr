require "./lib_llvm_c"

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

    struct BasicBlock
        def initialize (@value : LibLLVM_C::BasicBlockRef)
        end

        def to_unsafe
            @value
        end

        def instructions
            pins = LibLLVM_C.get_first_instruction(@value)
            while pins
                yield pins
                pins = LibLLVM_C.get_next_instruction(pins)
            end
        end

        def terminator
            return LibLLVM_C.get_basic_block_terminator(@value)
        end

        def successors
            pins = terminator
            raise "Basic block has no terminator" unless pins
            (0...LibLLVM_C.get_num_successors(pins)).each do |i|
                yield BasicBlock.new(LibLLVM_C.get_successor(pins, i))
            end
        end

        def_equals @value
        def_hash @value
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
            pfunc = LibLLVM_C.get_first_function(@value)
            while pfunc
                yield Function.new(pfunc)
                pfunc = LibLLVM_C.get_next_function(pfunc)
            end
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
end

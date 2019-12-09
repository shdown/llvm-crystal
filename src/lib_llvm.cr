require "./lib_llvm_c"

private lib LibCString
    fun strlen (s : LibC::Char*) : LibC::SizeT
end

module LibLLVM

def self.slurp_string (pmsg : LibC::Char*) : String
    return "" unless pmsg
    msg = String.new(pmsg)
    LibLLVM_C.dispose_message(pmsg)
    msg
end

def self.slurp_to_io (pmsg : LibC::Char*, io) : Nil
    return unless pmsg
    io.write Bytes.new(pmsg, LibCString.strlen(pmsg))
    LibLLVM_C.dispose_message(pmsg)
end

private module ValueMethods
    def initialize (@value : LibLLVM_C::ValueRef)
    end

    def to_s (io)
        LibLLVM.slurp_to_io(LibLLVM_C.print_value_to_string(@value), io)
        self
    end

    def name
        pname = LibLLVM_C.get_value_name2(@value, out nname)
        String.new(pname, nname)
    end

    def kind
        LibLLVM_C.get_value_kind(@value)
    end

    def type
        Type.new(LibLLVM_C.type_of(@value))
    end

    def to_any
        Any.new(@value)
    end

    def to_unsafe
        @value
    end

    def_equals @value
    def_hash @value
end

struct Any
    include ValueMethods

    def zero_extended_int_value
        LibLLVM_C.const_int_get_z_ext_value(@value)
    end

    def const_opcode
        LibLLVM_C.get_const_opcode(@value)
    end

    def const_operands
        OperandCollection.new(@value)
    end

    def global_initializer
        p = LibLLVM_C.get_initializer(@value)
        p ? Any.new(p) : nil
    end

    def const_string?
        LibLLVM_C.is_constant_string(@value) != 0
    end

    def to_const_string
        buf = LibLLVM_C.get_as_string(@value, out nbuf)
        Bytes.new(buf, nbuf).to_a
    end
end

class MemoryBuffer
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

class Module
    def initialize (@value : LibLLVM_C::ModuleRef)
    end

    def functions
        FunctionCollection.new(self)
    end

    def to_unsafe
        @value
    end

    def finalize
        LibLLVM_C.dispose_module(@value)
    end

    def_equals @value
    def_hash @value
end

struct Instruction
    include ValueMethods

    def successors
        SuccessorCollection.new(@value)
    end

    def incoming
        IncomingCollection.new(@value)
    end

    def conditional?
        LibLLVM_C.is_conditional(@value) != 0
    end

    def condition
        Any.new(LibLLVM_C.get_condition(@value))
    end

    def opcode
        LibLLVM_C.get_instruction_opcode(@value)
    end

    def alloca_type
        Type.new(LibLLVM_C.get_allocated_type(@value))
    end

    def callee
        Any.new(LibLLVM_C.get_called_value(@value))
    end

    def call_nargs
        LibLLVM_C.get_num_arg_operands(@value)
    end

    def icmp_predicate
        LibLLVM_C.get_i_cmp_predicate(@value)
    end

    def operands
        OperandCollection.new(@value)
    end
end

struct BasicBlock
    def initialize (@value : LibLLVM_C::BasicBlockRef)
    end

    def instructions
        InstructionCollection.new(@value)
    end

    def terminator
        pins = LibLLVM_C.get_basic_block_terminator(@value)
        raise "Basic block has no terminator" unless pins
        Instruction.new(pins)
    end

    def to_unsafe
        @value
    end

    def_equals @value
    def_hash @value
end

struct Type
    def initialize (@value : LibLLVM_C::TypeRef)
    end

    def self.new_void
        self.new(LibLLVM_C.void_type)
    end

    def self.new_integral (nbits)
        self.new(LibLLVM_C.int_type(nbits))
    end

    def self.new_array (elem_type, length)
        self.new(LibLLVM_C.array_type(elem_type, length))
    end

    def kind
        LibLLVM_C.get_type_kind(@value)
    end

    def pointer?
        kind.pointer_type_kind?
    end

    def void?
        kind.void_type_kind?
    end

    def integer?
        kind.integer_type_kind?
    end

    def array?
        kind.array_type_kind?
    end

    def struct?
        kind.struct_type_kind?
    end

    def integer_width
        LibLLVM_C.get_int_type_width(@value)
    end

    def opaque_struct?
        LibLLVM_C.is_opaque_struct(@value) != 0
    end

    def packed_struct?
        LibLLVM_C.is_packed_struct(@value) != 0
    end

    def element_type
        Type.new(LibLLVM_C.get_element_type(@value))
    end

    def return_type
        Type.new(LibLLVM_C.get_return_type(@value))
    end

    def var_args?
        LibLLVM_C.is_function_var_arg(@value) != 0
    end

    def array_length
        LibLLVM_C.get_array_length(@value)
    end

    def struct_elems
        raise "Trying to enumerate elements of an opaque struct" if opaque_struct?
        StructElemCollection.new(@value)
    end

    def to_unsafe
        @value
    end

    def_equals @value
    def_hash @value
end

struct Function
    include ValueMethods

    def declaration?
        LibLLVM_C.is_declaration(@value) != 0
    end

    def entry_basic_block
        BasicBlock.new(LibLLVM_C.get_entry_basic_block(@value))
    end

    def function_type
        ty = type
        if ty.pointer?
            ty = ty.element_type
        end
        ty
    end

    def params
        ParameterCollection.new(@value)
    end
end

def self.buffer_from_file (path)
    if LibLLVM_C.create_memory_buffer_with_contents_of_file(path, out pbuf, out pmsg) != 0
        raise "Cannot open bitcode file: " + slurp_string(pmsg)
    end
    return MemoryBuffer.new(pbuf)
end

def self.module_from_buffer (buf)
    raise "Cannot parse bitcode" unless LibLLVM_C.parse_bitcode2(buf, out pmodule) == 0
    return Module.new(pmodule)
end

private struct ParameterCollection
    include Indexable(Any)

    def initialize (func : LibLLVM_C::ValueRef)
        @size = LibLLVM_C.count_params(func)
        @data = Pointer(LibLLVM_C::ValueRef).malloc(@size)
        LibLLVM_C.get_params(func, @data)
    end

    def size
        @size
    end

    def unsafe_fetch (i)
        Any.new(@data[i])
    end
end

private struct SuccessorCollection
    include Indexable(BasicBlock)

    def initialize (@instr : LibLLVM_C::ValueRef)
        @size = LibLLVM_C.get_num_successors(@instr)
    end

    def size
        @size
    end

    def unsafe_fetch (i)
        BasicBlock.new(LibLLVM_C.get_successor(@instr, i))
    end
end

private struct OperandCollection
    include Indexable(Any)

    def initialize (@instr : LibLLVM_C::ValueRef)
        @size = LibLLVM_C.get_num_operands(@instr)
    end

    def size
        @size
    end

    def unsafe_fetch (i)
        Any.new(LibLLVM_C.get_operand(@instr, i))
    end
end

private struct StructElemCollection
    include Indexable(Type)

    def initialize (@type : LibLLVM_C::TypeRef)
        @size = LibLLVM_C.count_struct_element_types(@type)
    end

    def size
        @size
    end

    def unsafe_fetch (i)
        Type.new(LibLLVM_C.struct_get_type_at_index(@type, i))
    end
end

private struct IncomingCollection
    include Indexable(Tuple(BasicBlock, Any))

    def initialize (@instr : LibLLVM_C::ValueRef)
        @size = LibLLVM_C.count_incoming(@instr)
    end

    def size
        @size
    end

    def unsafe_fetch (i)
        {
            BasicBlock.new(LibLLVM_C.get_incoming_block(@instr, i)),
            Any.new(LibLLVM_C.get_incoming_value(@instr, i))
        }
    end
end

private struct FunctionCollection
    include Enumerable(Function)

    def initialize (@owner : Module)
    end

    def each
        pfunc = LibLLVM_C.get_first_function(@owner)
        while pfunc
            yield Function.new(pfunc)
            pfunc = LibLLVM_C.get_next_function(pfunc)
        end
    end

    def []? (name)
        pfunc = LibLLVM_C.get_named_function(@owner, name)
        pfunc ? Function.new(pfunc) : nil
    end

    def [] (name)
        self[name]? || raise "Cannot find function named '#{name}'"
    end
end

private struct InstructionCollection
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

require "crystal/pointer_linked_list"

struct Crystal::PointerLinkedList(T)
  def clear : Nil
    @head = Pointer(T).null
  end
end

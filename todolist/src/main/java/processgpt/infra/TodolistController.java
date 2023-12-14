package processgpt.infra;

import java.util.Optional;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.transaction.Transactional;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import processgpt.domain.*;

//<<< Clean Arch / Inbound Adaptor

@RestController
// @RequestMapping(value="/todolist")
@Transactional
public class TodolistController {

    @Autowired
    TodolistRepository todolistRepository;

    @RequestMapping(
        value = "todolist/{id}//todolist/{id}",
        method = RequestMethod.PUT,
        produces = "application/json;charset=UTF-8"
    )
    public Todolist updateTodolist(
        @PathVariable(value = "id") String id,
        @RequestBody UpdateTodolistCommand updateTodolistCommand,
        HttpServletRequest request,
        HttpServletResponse response
    ) throws Exception {
        System.out.println("##### /todolist/updateTodolist  called #####");
        Optional<Todolist> optionalTodolist = todolistRepository.findById(id);

        optionalTodolist.orElseThrow(() -> new Exception("No Entity Found"));
        Todolist todolist = optionalTodolist.get();
        todolist.updateTodolist(updateTodolistCommand);

        todolistRepository.save(todolist);
        return todolist;
    }
}
//>>> Clean Arch / Inbound Adaptor

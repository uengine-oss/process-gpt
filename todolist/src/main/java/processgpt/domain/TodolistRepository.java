package processgpt.domain;

import org.springframework.data.repository.PagingAndSortingRepository;
import org.springframework.data.rest.core.annotation.RepositoryRestResource;
import processgpt.domain.*;

//<<< PoEAA / Repository
@RepositoryRestResource(collectionResourceRel = "todolist", path = "todolist")
public interface TodolistRepository
    extends PagingAndSortingRepository<Todolist, String> {}

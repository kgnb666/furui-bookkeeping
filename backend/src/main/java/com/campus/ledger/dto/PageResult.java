package com.campus.ledger.dto;

import com.baomidou.mybatisplus.extension.plugins.pagination.Page;

import java.util.List;
import java.util.function.Function;

public class PageResult<T> {

    private long total;
    private long page;
    private long size;
    private List<T> list;

    public static <E, T> PageResult<T> of(Page<E> source, Function<E, T> mapper) {
        PageResult<T> result = new PageResult<>();
        result.total = source.getTotal();
        result.page = source.getCurrent();
        result.size = source.getSize();
        result.list = source.getRecords().stream().map(mapper).toList();
        return result;
    }

    public long getTotal() {
        return total;
    }

    public void setTotal(long total) {
        this.total = total;
    }

    public long getPage() {
        return page;
    }

    public void setPage(long page) {
        this.page = page;
    }

    public long getSize() {
        return size;
    }

    public void setSize(long size) {
        this.size = size;
    }

    public List<T> getList() {
        return list;
    }

    public void setList(List<T> list) {
        this.list = list;
    }
}

const script = new URL("./delta.py", import.meta.url).pathname;
const encoder = new TextDecoder();

function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

async function fixture(
  operator: boolean,
  body: (
    dir: string,
    write: (path: string, text: string) => Promise<void>,
  ) => Promise<void>,
) {
  const dir = await Deno.makeTempDir({ prefix: "axe-delta-" });
  const write = async (path: string, text: string) => {
    const target = `${dir}/${path}`;
    await Deno.mkdir(target.slice(0, target.lastIndexOf("/")), {
      recursive: true,
    });
    await Deno.writeTextFile(target, text);
  };
  try {
    await write("docs/main.md", "# Application\n### [look]\n### [test]\n");
    if (operator) await write("axe.toml", '[workflow]\nreview = "operators"\n');
    await body(dir, write);
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

async function run(dir: string) {
  const result = await new Deno.Command("python3", {
    args: [script],
    cwd: dir,
    stdout: "piped",
    stderr: "piped",
  }).output();
  return {
    code: result.code,
    stderr: encoder.decode(result.stderr),
    report: await Deno.readTextFile(`${dir}/.axe/delta-report.md`),
  };
}

async function seed(dir: string) {
  await Deno.mkdir(`${dir}/.axe/freeze`, { recursive: true });
  await Deno.copyFile(`${dir}/docs/main.md`, `${dir}/.axe/freeze/main.md`);
}

Deno.test("operator mode refuses to invent an implemented baseline", async () => {
  await fixture(true, async (dir) => {
    const result = await run(dir);
    assert(result.code === 2, result.stderr);
    const missing = await Deno.stat(`${dir}/.axe/freeze`).then(
      () => false,
      () => true,
    );
    assert(missing, "A missing baseline must not advance freeze");
  });
});

Deno.test("default baseline behavior is preserved", async () => {
  await fixture(false, async (dir) => {
    assert((await run(dir)).code === 2, "Expected baseline result");
    assert(
      (await run(dir)).report.startsWith("status: empty"),
      "Expected identical baseline",
    );
  });
});

Deno.test("operator handoff separates visual acceptance from automation", async () => {
  await fixture(true, async (dir, write) => {
    await seed(dir);
    await write("docs/mockup/screens/task.html", "<main>Task</main>");
    await write(
      "docs/task_page.md",
      "# Task\n[Screen](mockup/screens/task.html)\n",
    );
    const result = await run(dir);
    assert(result.code === 0, result.report);
    assert(
      result.report.includes("docs/mockup/screens/task.html"),
      "Missing affected screen",
    );
    assert(
      result.report.includes("visual acceptance: pending"),
      "Missing visual handoff",
    );
    const verify = result.report.split("## Verify")[1];
    assert(
      !verify.includes("compare"),
      "Implementer must not perform visual acceptance",
    );
    assert(
      verify.includes("build the project"),
      "Automation must remain required",
    );
    assert(
      !(await Deno.stat(`${dir}/.axe/freeze/task_page.md`).then(
        () => true,
        () => false,
      )),
      "Report must not advance freeze",
    );
  });
});

Deno.test("default mode retains its visual verification", async () => {
  await fixture(false, async (dir, write) => {
    await seed(dir);
    await write("docs/mockup/screens/task.html", "<main>Task</main>");
    await write(
      "docs/task_page.md",
      "# Task\n[Screen](mockup/screens/task.html)\n",
    );
    const result = await run(dir);
    assert(result.code === 0, result.report);
    assert(
      result.report.split("## Verify")[1].includes("compare the Look screens"),
      "Default visual check lost",
    );
  });
});

Deno.test("spec links are inspected outside operator implementation; syntax still blocks", async () => {
  for (const operator of [false, true]) {
    await fixture(operator, async (dir, write) => {
      await seed(dir);
      await write("docs/rule.md", "# Rule\n[Missing](missing.md)\n");
      assert(
        (await run(dir)).code === (operator ? 0 : 1),
        "Wrong review responsibility",
      );
      await write("docs/schema.json", "{broken");
      assert((await run(dir)).code === 1, "Invalid machine syntax must block");
      await Deno.remove(`${dir}/docs/schema.json`);
      await write("docs/rpc.md", "# RPC\n```toml\n[broken\n```\n");
      assert((await run(dir)).code === 1, "Invalid contract TOML must block");
    });
  }
});

Deno.test("removing a contract schedules contract compilation", async () => {
  await fixture(true, async (dir, write) => {
    await seed(dir);
    await write(
      ".axe/freeze/rpc.md",
      "# RPC\n```toml\n[Service.method]\n```\n",
    );
    const result = await run(dir);
    assert(result.code === 0, result.report);
    assert(
      result.report.includes("project contract build"),
      "Deleted contract still needs projection",
    );
  });
});

Deno.test("unchanged operator docs allow caller to select a bounded repair without freeze changes", async () => {
  await fixture(true, async (dir) => {
    await seed(dir);
    const before = await Deno.stat(`${dir}/.axe/freeze/main.md`);
    const result = await run(dir);
    assert(
      result.code === 0 && result.report.startsWith("status: empty"),
      result.report,
    );
    const after = await Deno.stat(`${dir}/.axe/freeze/main.md`);
    assert(
      before.mtime?.getTime() === after.mtime?.getTime(),
      "Unchanged docs must not advance freeze",
    );
  });
});
